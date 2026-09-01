#!/usr/bin/env bash
set -euo pipefail

# Decide whether HEAD is a release, and if so, tag it.
#
#   admin/build/tag-release.sh [--dry-run]
#
# What makes a push a release is its COMMIT SUBJECT, not the contents of
# VERSION. `release.sh` writes the version into the subject, so the subject is
# the author's explicit claim:
#
#   "site v0.1.4: shorter treatments copy"   -> a release, held to the contract
#   "fix a typo in the footer"               -> an ordinary push, tagged nothing
#
# The asymmetry is deliberate, and it is the whole point of this script.
# Deriving release-ness from VERSION alone means every ordinary push after a
# release fails the "already tagged" check - and because the deploy job
# requires this job to be success OR skipped, a failure here is an outage
# rather than a bookkeeping gap. A missing tag costs an audit-trail row. A
# blocked deploy costs the site.
#
# So: ordinary pushes exit 0 and publish. A commit that CLAIMS a version is
# held to the full contract - subject and VERSION agree, the version has not
# already shipped, and it is the immediate successor of the last tag.

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

cd "$(git rev-parse --show-toplevel)"

SUBJECT="$(git log -1 --pretty=%s)"

if [[ ! "$SUBJECT" =~ ^site\ v[0-9]+\.[0-9]+\.[0-9]+: ]]; then
  echo "ordinary push - no version claimed in the commit subject, nothing to tag"
  echo "  subject: $SUBJECT"
  exit 0
fi

CLAIMED="$(sed -E 's/^site (v[0-9]+\.[0-9]+\.[0-9]+):.*/\1/' <<<"$SUBJECT")"
FILE_VERSION="$(tr -d '[:space:]' < VERSION)"

echo "release commit: claims $CLAIMED"

# 1. the subject and the file must agree
if [[ "$CLAIMED" != "$FILE_VERSION" ]]; then
  echo "FAIL commit subject claims $CLAIMED but VERSION says $FILE_VERSION" >&2
  echo "     bump VERSION and the subject together, or drop the 'site vX.Y.Z:' prefix" >&2
  exit 1
fi

# 2. the version must not already have shipped
if git rev-parse -q --verify "refs/tags/$CLAIMED" >/dev/null; then
  echo "FAIL $CLAIMED has already shipped (tag exists at $(git rev-parse --short "$CLAIMED"))" >&2
  echo "     a released version is immutable; bump to the next one" >&2
  exit 1
fi

# 3. it must be the immediate successor of the newest tag
LAST="$(git tag -l 'v*' --sort=-v:refname | head -n1)"
if [[ -z "$LAST" ]]; then
  echo "  no previous tag - $CLAIMED is the first release"
else
  IFS=. read -r lmaj lmin lpat <<<"${LAST#v}"
  IFS=. read -r cmaj cmin cpat <<<"${CLAIMED#v}"
  if   [[ "$cmaj" == "$lmaj" && "$cmin" == "$lmin" && "$cpat" == "$((lpat + 1))" ]]; then :
  elif [[ "$cmaj" == "$lmaj" && "$cmin" == "$((lmin + 1))" && "$cpat" == "0" ]]; then :
  elif [[ "$cmaj" == "$((lmaj + 1))" && "$cmin" == "0" && "$cpat" == "0" ]]; then :
  else
    echo "FAIL $CLAIMED does not follow $LAST" >&2
    echo "     expected v$lmaj.$lmin.$((lpat + 1)), v$lmaj.$((lmin + 1)).0 or v$((lmaj + 1)).0.0" >&2
    exit 1
  fi
  echo "  follows $LAST"
fi

if (( DRY_RUN )); then
  echo "DRY RUN would tag $(git rev-parse --short HEAD) as $CLAIMED"
  exit 0
fi

git tag -a "$CLAIMED" -m "$SUBJECT"

# Note for anyone debugging a rejected push: a workflow's GITHUB_TOKEN cannot
# push a tag pointing at a commit whose tree carries a different version of a
# workflow file. Tagging HEAD of the deploy branch is always safe, because
# HEAD's workflow blob is the one running.
git push origin "$CLAIMED"

echo "tagged $CLAIMED at $(git rev-parse --short HEAD)"
