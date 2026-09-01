#!/usr/bin/env bash
set -uo pipefail

# Prove the checks fail when they should.
#
#   admin/build/selftest.sh
#
# A validator that has only ever been run against a passing tree is not
# evidence of anything. This copies the repository into a throwaway directory,
# breaks it one way at a time, and asserts the exit code - and does the same
# for the tag contract, over the cases that decide whether a push tags,
# publishes, or is refused.
#
# Nothing here touches the real working tree.

cd "$(git rev-parse --show-toplevel)"
REPO="$PWD"

PASS=0
FAIL=0
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

# A throwaway git clone of the current tree, including uncommitted work.
fresh() {
  local dir="$TMPROOT/case-$RANDOM$RANDOM"
  mkdir -p "$dir"
  tar -c --exclude=.git -C "$REPO" . | tar -x -C "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email t@example.invalid
  git -C "$dir" config user.name  Test
  git -C "$dir" add -A
  git -C "$dir" commit -qm "baseline"
  echo "$dir"
}

check() { # check <expected-exit> <name> <dir> <command...>
  local want="$1" name="$2" dir="$3"; shift 3
  local out rc
  out="$(cd "$dir" && "$@" 2>&1)"; rc=$?
  if [[ "$rc" == "$want" ]]; then
    printf '  ok   %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf '  FAIL %s (exit %s, wanted %s)\n' "$name" "$rc" "$want"
    printf '%s\n' "$out" | sed 's/^/         | /' | tail -n 6
    FAIL=$((FAIL + 1))
  fi
}

VALIDATE=(node admin/build/validate.js)

echo "== the validator passes a clean tree"
d="$(fresh)"
check 0 "clean tree passes" "$d" "${VALIDATE[@]}"

echo
echo "== the validator rejects a broken tree"

d="$(fresh)"
sed -i 's|href="treatments/"|href="treatmnets/"|' "$d/index.html"
check 1 "broken internal link" "$d" "${VALIDATE[@]}"

d="$(fresh)"
sed -i 's|href="treatments/"|href="/treatments/"|' "$d/index.html"
check 1 "root-absolute link (breaks on a sub-path)" "$d" "${VALIDATE[@]}"

d="$(fresh)"
# A page that exists, validates, deploys - and that nothing links to.
sed 's|<title>Treatments|<title>Orphan|; s|treatments/"|orphan.html"|' \
  "$d/treatments/index.html" > "$d/orphan.html"
node -e '
  const fs=require("fs"),p=process.argv[1];
  let h=fs.readFileSync(p,"utf8");
  h=h.replace(/href="\.\.\/assets/,"href=\"assets").replace(/href="\.\.\/"/,"href=\"./\"");
  h=h.replace(/(rel="canonical" href=")[^"]*/,"$1https://sportshealingcalendar-ops.github.io/Chiswick-Knee-Clinic/orphan.html");
  fs.writeFileSync(p,h);
' "$d/orphan.html"
(cd "$d" && node admin/build/build.js >/dev/null 2>&1)
check 1 "orphan page" "$d" "${VALIDATE[@]}"

d="$(fresh)"
sed -i 's|content="v0\.|content="v9.|' "$d/index.html"
check 1 "stale version stamp" "$d" "${VALIDATE[@]}"

d="$(fresh)"
printf 'v0.9.9\n' > "$d/VERSION"
check 1 "VERSION bumped without re-running the build" "$d" "${VALIDATE[@]}"

d="$(fresh)"
sed -i 's|<h1>Specialist knee care|<h1>Guaranteed knee care|' "$d/index.html"
check 1 "banned advertising claim" "$d" "${VALIDATE[@]}"

d="$(fresh)"
sed -i 's|<link rel="canonical"[^>]*>||' "$d/index.html"
check 1 "missing canonical URL" "$d" "${VALIDATE[@]}"

d="$(fresh)"
node -e 'const fs=require("fs");const p=process.argv[1];fs.writeFileSync(p,fs.readFileSync(p,"utf8").replace(/<script type="application\/ld\+json">[\s\S]*?<\/script>/,"<script type=\"application/ld+json\">{ not json }</script>"))' "$d/index.html"
check 1 "malformed JSON-LD" "$d" "${VALIDATE[@]}"

d="$(fresh)"
# Assembled at runtime so this script is not itself a tripwire hit. This is
# AWS's own documented example key - it grants nothing.
FAKE_AWS="AKIA$(printf 'IOSFODNN7EXAMPLE')"
printf 'aws_access_key_id = %s\n' "$FAKE_AWS" > "$d/deploy-notes.txt"
git -C "$d" add -A && git -C "$d" commit -qm "leak"
check 1 "committed credential (secret tripwire)" "$d" "${VALIDATE[@]}"

d="$(fresh)"
printf '%s\n' "$FAKE_AWS" > "$d/admin/build/.secret-strings"
printf 'nothing to see: %s\n' "$FAKE_AWS" > "$d/notes.txt"
git -C "$d" add -A -f && git -C "$d" commit -qm "literal leak"
check 1 "known-secret literal tripwire" "$d" "${VALIDATE[@]}"

echo
echo "== the tag contract"

TAG=(bash admin/build/tag-release.sh --dry-run)

# Build a release commit in a throwaway repo: set VERSION, commit with the
# given subject.
#
# The scratch file is what makes this correct rather than convenient. These
# fixtures set VERSION to literal values, and `fresh` copies the CURRENT tree -
# so the first time the repo's own VERSION reached a fixture value, that write
# became a no-op, `git commit` found nothing to commit, and the case silently
# ran against the baseline commit instead. Two cases failed; a third
# ("first release tags") kept reporting ok, because a baseline commit is an
# ordinary push and exits 0 for the wrong reason.
#
# So: always produce a real commit, and assert the subject actually landed.
# A fixture that does not build what it claims must fail loudly, never pass.
stage() { # stage <dir> <version|-> <subject>
  local dir="$1" version="$2" subject="$3"
  [[ "$version" != "-" ]] && printf '%s\n' "$version" > "$dir/VERSION"
  printf 'fixture: %s\n' "$subject" > "$dir/.selftest-fixture"
  git -C "$dir" add -A
  if ! git -C "$dir" commit -qm "$subject"; then
    printf '  FAIL fixture built no commit: %s\n' "$subject"
    FAIL=$((FAIL + 1))
    return 1
  fi
  local landed
  landed="$(git -C "$dir" log -1 --pretty=%s)"
  if [[ "$landed" != "$subject" ]]; then
    printf '  FAIL fixture subject is "%s", wanted "%s"\n' "$landed" "$subject"
    FAIL=$((FAIL + 1))
    return 1
  fi
}

d="$(fresh)"
stage "$d" - "fix a typo in the footer" &&
  check 0 "ordinary push tags nothing and still publishes" "$d" "${TAG[@]}"

d="$(fresh)"
stage "$d" v0.1.1 "site v0.1.1: first release" &&
  check 0 "first release tags" "$d" "${TAG[@]}"

d="$(fresh)"
stage "$d" v0.1.1 "site v0.1.4: skipped ahead" &&
  check 1 "subject and VERSION disagree" "$d" "${TAG[@]}"

d="$(fresh)"
stage "$d" v0.1.1 "site v0.1.1: first release" &&
  git -C "$d" tag -a v0.1.1 -m existing &&
  check 1 "reusing a shipped version" "$d" "${TAG[@]}"

d="$(fresh)"
git -C "$d" tag -a v0.1.1 -m shipped
stage "$d" v0.1.5 "site v0.1.5: skips v0.1.2" &&
  check 1 "skipping a version" "$d" "${TAG[@]}"

d="$(fresh)"
git -C "$d" tag -a v0.1.1 -m shipped
stage "$d" v0.2.0 "site v0.2.0: minor bump" &&
  check 0 "minor bump follows a patch release" "$d" "${TAG[@]}"

d="$(fresh)"
git -C "$d" tag -a v0.1.1 -m shipped
stage "$d" - "an ordinary push after a release" &&
  check 0 "ordinary push after a release is not held to the contract" "$d" "${TAG[@]}"

echo
echo "------------------------------------------------------------"
if (( FAIL )); then
  echo "SELFTEST FAILED: $FAIL of $((PASS + FAIL)) cases"
  exit 1
fi
echo "SELFTEST PASSED all $PASS cases"
