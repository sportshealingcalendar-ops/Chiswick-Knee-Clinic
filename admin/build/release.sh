#!/usr/bin/env bash
set -euo pipefail

# One command per release, deliberately strict.
#
#   admin/build/release.sh "shorter treatments copy"
#
#   1. bump    - VERSION patch +1
#   2. build   - regenerate version stamps, sitemap.xml, robots.txt
#   3. test    - the full validator; any failure aborts before anything is pushed
#   4. push    - commit as "site vX.Y.Z: <message>", push to the deploy branch
#   5. verify  - wait for the live site to actually serve the new version
#
# Nothing is pushed until the validator passes, so the secret tripwire and the
# structural checks gate the history, not just the deployment. And the run does
# not end at "pushed": it ends when a reader could load the change, or loudly
# when they could not.
#
# Options:
#   --minor / --major   bump that component instead of the patch
#   --no-verify         skip step 5 (you are then responsible for checking)

cd "$(git rev-parse --show-toplevel)"

BUMP=patch
VERIFY=1
ARGS=()
for a in "$@"; do
  case "$a" in
    --minor)      BUMP=minor ;;
    --major)      BUMP=major ;;
    --no-verify)  VERIFY=0 ;;
    *)            ARGS+=("$a") ;;
  esac
done

if (( ${#ARGS[@]} != 1 )); then
  echo "usage: admin/build/release.sh [--minor|--major] [--no-verify] \"what changed\"" >&2
  exit 2
fi
MESSAGE="${ARGS[0]}"

BRANCH="$(node -e 'process.stdout.write(require("./admin/build/site.json").deployBranch)')"
CURRENT="$(git rev-parse --abbrev-ref HEAD)"

echo "== 1/5 bump"
IFS=. read -r maj min pat <<<"$(tr -d '[:space:]v' < VERSION)"
case "$BUMP" in
  patch) pat=$((pat + 1)) ;;
  minor) min=$((min + 1)); pat=0 ;;
  major) maj=$((maj + 1)); min=0; pat=0 ;;
esac
VERSION="v$maj.$min.$pat"
echo "$VERSION" > VERSION
echo "   $VERSION"

echo "== 2/5 build"
node admin/build/build.js

echo "== 3/5 test"
if ! node admin/build/validate.js; then
  echo >&2
  echo "aborted: validation failed, nothing was committed or pushed." >&2
  echo "VERSION has been bumped to $VERSION locally - fix the failures and re-run" >&2
  echo "with --no-verify off, or 'git checkout VERSION' to reset the bump." >&2
  exit 1
fi

echo "== 4/5 push"
git add -A
git commit -m "site $VERSION: $MESSAGE"
git push -u origin "$CURRENT"
if [[ "$CURRENT" != "$BRANCH" ]]; then
  echo "   pushed $CURRENT (not the deploy branch $BRANCH) - Pages deploys from $BRANCH,"
  echo "   so this release goes live when $CURRENT reaches it."
  VERIFY=0
fi
LOCAL="$(git rev-parse HEAD)"
REMOTE="$(git rev-parse "origin/$CURRENT")"
[[ "$LOCAL" == "$REMOTE" ]] || { echo "FAIL local HEAD != origin/$CURRENT" >&2; exit 1; }
echo "   $CURRENT in sync with origin at ${LOCAL:0:7}"

if (( VERIFY )); then
  echo "== 5/5 verify"
  admin/build/verify-live.sh
else
  echo "== 5/5 verify (skipped)"
  echo "   the release is not proven live. Check the Actions run before saying it is."
fi

echo
echo "release $VERSION complete"
