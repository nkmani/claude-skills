#!/usr/bin/env bash
# Exit 0 if the PR head SHA differs from state.last_reviewed_sha (i.e. new
# commits to review). Exit 1 if nothing new. Exit 2+ on error.
#
# Usage: has-new-commits.sh <pr>
#
# Prints the current head SHA to stdout when 0/1; nothing on error.

set -euo pipefail

pr="${1:-}"
if [[ -z "$pr" ]]; then
  echo "usage: has-new-commits.sh <pr>" >&2
  exit 2
fi

here="$(cd "$(dirname "$0")" && pwd)"

head_sha=$(gh pr view "$pr" --json headRefOid -q .headRefOid 2>/dev/null || true)
if [[ -z "$head_sha" ]]; then
  echo "has-new-commits.sh: could not read head SHA for PR #$pr" >&2
  exit 3
fi

last_sha=$("$here/state.sh" get "$pr" last_reviewed_sha 2>/dev/null || true)

echo "$head_sha"
if [[ "$head_sha" != "$last_sha" ]]; then
  exit 0
else
  exit 1
fi
