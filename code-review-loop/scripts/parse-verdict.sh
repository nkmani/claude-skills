#!/usr/bin/env bash
# Read the latest review on a PR, derive a verdict (APPROVE or REQUEST_CHANGES),
# and update the state file with it. Also stamps last_reviewed_sha and bumps
# iteration. Intended to be called by the reviewer right after posting its
# review.
#
# Usage: parse-verdict.sh <pr>
#
# Verdict resolution:
#   1. GitHub review state APPROVED          -> APPROVE
#   2. GitHub review state CHANGES_REQUESTED -> REQUEST_CHANGES
#   3. GitHub review state COMMENTED         -> grep body for a sentinel line:
#        ^VERDICT:\s*APPROVE\s*$         -> APPROVE
#        ^VERDICT:\s*REQUEST_CHANGES\s*$ -> REQUEST_CHANGES
#        (neither)                       -> REQUEST_CHANGES (conservative)
#      Sentinels exist because GitHub forbids --approve/--request-changes on
#      the PR author's own PRs (solo-dev usage), so the reviewer must post via
#      --comment and encode the verdict in the body.
#   4. DISMISSED -> ignored (look at previous review)

set -euo pipefail

pr="${1:-}"
if [[ -z "$pr" ]]; then
  echo "usage: parse-verdict.sh <pr>" >&2
  exit 2
fi

here="$(cd "$(dirname "$0")" && pwd)"

latest=$(gh pr view "$pr" --json reviews -q \
  '[.reviews[] | select(.state != "DISMISSED")] | last' 2>/dev/null || true)

if [[ -z "$latest" || "$latest" == "null" ]]; then
  echo "parse-verdict.sh: no reviews found on PR #$pr" >&2
  exit 4
fi

review_state=$(echo "$latest" | jq -r '.state')
review_body=$(echo "$latest"  | jq -r '.body // ""')

case "$review_state" in
  APPROVED)          verdict="APPROVE" ;;
  CHANGES_REQUESTED) verdict="REQUEST_CHANGES" ;;
  COMMENTED)
    if   echo "$review_body" | grep -qE '^VERDICT:[[:space:]]*APPROVE[[:space:]]*$'; then
      verdict="APPROVE"
    elif echo "$review_body" | grep -qE '^VERDICT:[[:space:]]*REQUEST_CHANGES[[:space:]]*$'; then
      verdict="REQUEST_CHANGES"
    else
      verdict="REQUEST_CHANGES"
    fi
    ;;
  *) echo "parse-verdict.sh: unexpected state $review_state" >&2; exit 5 ;;
esac

head_sha=$(gh pr view "$pr" --json headRefOid -q .headRefOid)
iter=$("$here/state.sh" get "$pr" iteration)
iter=$(( iter + 1 ))

"$here/state.sh" set "$pr" last_verdict "$verdict"
"$here/state.sh" set "$pr" last_reviewed_sha "$head_sha"
"$here/state.sh" set "$pr" iteration "$iter"
"$here/state.sh" set "$pr" status in_review

echo "$verdict"
