#!/usr/bin/env bash
# Spawn a reviewer session in a new Terminal.app window. The new window cd's
# into the current repo root and runs `claude` with a /loop kickoff prompt.
#
# Usage: spawn-reviewer.sh <pr> [interval]   (interval defaults to 5m)
#
# Falls back to printing the command for manual paste if osascript / Terminal
# is unavailable (e.g. headless SSH).

set -euo pipefail

pr="${1:-}"
interval="${2:-5m}"

if [[ -z "$pr" ]]; then
  echo "usage: spawn-reviewer.sh <pr> [interval]" >&2
  exit 2
fi

repo_root=$(git rev-parse --show-toplevel)
prompt="/loop ${interval} /code-review-loop review ${pr}"

# Build the command the new Terminal window will run.
# We chain: cd repo && claude with an initial prompt.
#
# Quoting notes:
#   - Avoid ${var@Q} (bash 4.4+); macOS /bin/bash is 3.2.
#   - Avoid printf %q: its backslash escapes get stripped by AppleScript's
#     string literal parser before the shell ever sees them.
#   - Plain single-quote wrapping works because repo_root and prompt are
#     controlled by this script (no embedded single quotes). Fails for repo
#     paths containing "'", but that's effectively never on macOS.
#
# CODEREV_LOOP_AUTO_CLOSE=1 marks this as a disposable spawned window so
# auto-close-terminal.sh will close it on the reviewer's final tick. The
# implementer's primary session has no such marker and is left alone.
shell_cmd="export CODEREV_LOOP_AUTO_CLOSE=1; cd '$repo_root' && claude '$prompt'"

echo "spawn-reviewer.sh: shell_cmd = $shell_cmd"

if [[ "$(uname -s)" != "Darwin" ]] || ! command -v osascript >/dev/null 2>&1; then
  echo "spawn-reviewer.sh: not on macOS or osascript missing." >&2
  echo "Run this in a second terminal manually:" >&2
  echo "  $shell_cmd" >&2
  exit 0
fi

if ! osascript <<APPLESCRIPT
tell application "Terminal"
    activate
    do script "$shell_cmd"
end tell
APPLESCRIPT
then
  echo "spawn-reviewer.sh: osascript failed. Run this manually:" >&2
  echo "  $shell_cmd" >&2
  exit 1
fi

echo "reviewer spawned in new Terminal window for PR #$pr (interval $interval)"
