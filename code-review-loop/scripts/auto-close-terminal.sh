#!/usr/bin/env bash
# Print a countdown and then close the front Terminal.app window.
#
# Usage: auto-close-terminal.sh [delay_seconds] [message]
#   delay_seconds: how long to wait before closing (default 15)
#   message:       short status line shown above the countdown
#
# Cancel: interrupt this command (Esc / Ctrl-C in Claude). The window will
# stay open and the bash exits cleanly without invoking osascript.
#
# Falls back to a no-op print on non-macOS / SSH (no osascript) so callers
# can invoke it unconditionally.

set -uo pipefail

delay="${1:-15}"
msg="${2:-Loop complete.}"

if ! [[ "$delay" =~ ^[0-9]+$ ]]; then
  echo "auto-close-terminal.sh: delay must be a non-negative integer, got: $delay" >&2
  exit 2
fi

cat <<EOF

════════════════════════════════════════════════════════════════
  ✓ $msg
  This Terminal window will auto-close in ${delay}s.
  To keep it open: press Esc (or Ctrl-C) to interrupt.
════════════════════════════════════════════════════════════════

EOF

# Trap interrupts so the user gets a clear "staying open" message instead of
# a bare ^C trace.
trap 'echo; echo "Cancelled — window staying open."; exit 0' INT TERM

for (( i=delay; i>0; i-- )); do
  printf "\r  closing in %2ds...  " "$i"
  sleep 1
done
printf "\r%-40s\n" "  closing now."

if [[ "$(uname -s)" != "Darwin" ]] || ! command -v osascript >/dev/null 2>&1; then
  echo "auto-close-terminal.sh: not on macOS / no osascript — leaving window open." >&2
  exit 0
fi

# Close the frontmost Terminal window. Backgrounded so the close signal isn't
# racing with this script's own exit.
osascript -e 'tell application "Terminal" to close (front window)' >/dev/null 2>&1 &
