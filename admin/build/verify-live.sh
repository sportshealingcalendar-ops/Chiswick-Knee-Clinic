#!/usr/bin/env bash
set -euo pipefail

# Ask the live site what version it is serving.
#
#   admin/build/verify-live.sh [url] [timeout-seconds]
#
# "Both remotes in sync" does not mean published. The bytes reaching GitHub and
# a reader being able to load them are different facts, separated by a Pages
# job with its own failure modes - most often a transient failure to download
# a third-party action, which no check on the repository side can see.
#
# So a release finishes by asking the origin, with a cache-buster, because the
# origin's own answer is the only one that counts.

cd "$(git rev-parse --show-toplevel)"

URL="${1:-$(node -e 'process.stdout.write(require("./admin/build/site.json").baseUrl)')}"
TIMEOUT="${2:-480}"
VERSION="$(tr -d '[:space:]' < VERSION)"
INTERVAL=10
DEADLINE=$(( $(date +%s) + TIMEOUT ))

echo "waiting for $VERSION to appear at $URL (up to $((TIMEOUT / 60)) min)"

attempt=0
while (( $(date +%s) < DEADLINE )); do
  attempt=$((attempt + 1))
  body="$(curl -fsSL --max-time 20 "${URL}?cb=$(date +%s)-$attempt" 2>/dev/null || true)"
  if grep -q "name=\"site-version\" content=\"$VERSION\"" <<<"$body"; then
    echo "live: the site is serving $VERSION (after ${attempt} check(s))"
    exit 0
  fi
  served="$(grep -o 'name="site-version" content="[^"]*"' <<<"$body" | head -n1 | sed -E 's/.*content="([^"]*)".*/\1/')"
  printf '  check %d: serving %s\n' "$attempt" "${served:-<no response>}"
  sleep "$INTERVAL"
done

cat >&2 <<EOF

FAIL $VERSION never appeared at $URL within $((TIMEOUT / 60)) minutes.

The push succeeded and the deploy did not reach readers. Check the Actions run
for this commit. A failure to download an action (HTTP 429 from codeload) is
transient and only needs the job re-running; anything else needs reading.

Until this passes, the site is serving an older version. Do not report the
change as live.
EOF
exit 1
