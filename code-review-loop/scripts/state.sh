#!/usr/bin/env bash
# State file helper for code-review-loop.
#
# Usage:
#   state.sh init <pr> <issue> <branch> [max_iter]
#   state.sh get  <pr> [field]
#   state.sh set  <pr> <field> <value>
#   state.sh path <pr>            # prints the state file path
#
# State file: ~/.claude/coderev-loop/<repo-basename>/<pr>.json
#
# Fields:
#   issue, pr, branch, base, max_iterations, iteration,
#   last_reviewed_sha, status, last_verdict, updated_at
#
# status         ∈ {implementing, in_review, approved, merged, failed}
# last_verdict   ∈ {null, APPROVE, REQUEST_CHANGES}

set -euo pipefail

cmd="${1:-}"; shift || true
pr="${1:-}"; shift || true

if [[ -z "$cmd" || -z "$pr" ]]; then
  echo "usage: state.sh {init|get|set|path} <pr> [...]" >&2
  exit 2
fi

repo_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
repo_basename=$(basename "$repo_root")
dir="$HOME/.claude/coderev-loop/$repo_basename"
file="$dir/$pr.json"

mkdir -p "$dir"

now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "state.sh: requires jq (brew install jq)" >&2
    exit 3
  fi
}

case "$cmd" in
  path)
    echo "$file"
    ;;

  init)
    issue="${1:-}"; branch="${2:-}"; max_iter="${3:-10}"
    if [[ -z "$issue" || -z "$branch" ]]; then
      echo "usage: state.sh init <pr> <issue> <branch> [max_iter]" >&2
      exit 2
    fi
    require_jq
    if [[ -e "$file" ]]; then
      echo "state.sh: $file already exists; refusing to clobber" >&2
      exit 4
    fi
    base=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@' || echo main)
    jq -n \
      --arg pr "$pr" \
      --arg issue "$issue" \
      --arg branch "$branch" \
      --arg base "$base" \
      --argjson max_iter "$max_iter" \
      --arg now "$(now_iso)" \
      '{
         pr: ($pr|tonumber),
         issue: ($issue|tonumber),
         branch: $branch,
         base: $base,
         max_iterations: $max_iter,
         iteration: 0,
         last_reviewed_sha: null,
         status: "implementing",
         last_verdict: null,
         updated_at: $now
       }' > "$file"
    echo "$file"
    ;;

  get)
    field="${1:-}"
    if [[ ! -e "$file" ]]; then
      echo "state.sh: no state file at $file" >&2
      exit 5
    fi
    require_jq
    if [[ -z "$field" ]]; then
      cat "$file"
    else
      jq -r ".${field} // empty" "$file"
    fi
    ;;

  set)
    field="${1:-}"; value="${2:-}"
    if [[ -z "$field" ]]; then
      echo "usage: state.sh set <pr> <field> <value>" >&2
      exit 2
    fi
    if [[ ! -e "$file" ]]; then
      echo "state.sh: no state file at $file" >&2
      exit 5
    fi
    require_jq
    # Numeric fields stay numeric; others stay strings; literal `null` is null.
    case "$field" in
      iteration|max_iterations|pr|issue)
        tmp=$(mktemp)
        jq --arg now "$(now_iso)" --argjson v "$value" \
           ".${field} = \$v | .updated_at = \$now" "$file" > "$tmp"
        mv "$tmp" "$file"
        ;;
      *)
        tmp=$(mktemp)
        if [[ "$value" == "null" ]]; then
          jq --arg now "$(now_iso)" \
             ".${field} = null | .updated_at = \$now" "$file" > "$tmp"
        else
          jq --arg now "$(now_iso)" --arg v "$value" \
             ".${field} = \$v | .updated_at = \$now" "$file" > "$tmp"
        fi
        mv "$tmp" "$file"
        ;;
    esac
    ;;

  *)
    echo "unknown command: $cmd" >&2
    exit 2
    ;;
esac
