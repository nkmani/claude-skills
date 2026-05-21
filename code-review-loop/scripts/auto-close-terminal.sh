#!/usr/bin/env bash
# Print a countdown and then close THIS Terminal.app window (the window
# containing the tab attached to this script's tty).
#
# Usage: auto-close-terminal.sh [delay_seconds] [message]
#   delay_seconds: how long to wait before closing (default 15)
#   message:       short status line shown above the countdown
#
# Gate: this script only closes the window when CODEREV_LOOP_AUTO_CLOSE=1.
# `spawn-reviewer.sh` sets that env var when launching the disposable
# reviewer window, so only spawned windows auto-close. The implementer's
# primary session can call this script harmlessly — it will just print a
# summary line and exit, leaving the user's main window alone.
#
# Cancel: interrupt this command (Esc / Ctrl-C in Claude). The window will
# stay open and the bash exits cleanly without invoking osascript.
#
# Falls back to a no-op print on non-macOS / SSH (no osascript) so callers
# can invoke it unconditionally.
#
# Note on `set -uo pipefail` (no -e): we want full control over the exit
# path so the INT/TERM trap can cleanly print "Cancelled" and exit 0
# without an unrelated `sleep` or `printf` failure short-circuiting the
# script via -e. Do not add -e back.

set -uo pipefail

delay="${1:-15}"
msg="${2:-Loop complete.}"

if ! [[ "$delay" =~ ^[0-9]+$ ]]; then
  echo "auto-close-terminal.sh: delay must be a non-negative integer, got: $delay" >&2
  exit 2
fi

# Env gate — only the spawned reviewer window opts in.
if [[ "${CODEREV_LOOP_AUTO_CLOSE:-}" != "1" ]]; then
  echo ""
  echo "✓ $msg (window left open — CODEREV_LOOP_AUTO_CLOSE not set)"
  exit 0
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

# Target THIS script's own window by tty, not the frontmost window — the
# user may have focused a different Terminal during the countdown.
my_tty=$(tty 2>/dev/null || true)
if [[ -z "$my_tty" || "$my_tty" == "not a tty" ]]; then
  echo "auto-close-terminal.sh: could not resolve own tty — leaving window open." >&2
  exit 0
fi

# Backgrounded so the close signal isn't racing with this script's own exit.
osascript >/dev/null 2>&1 <<APPLESCRIPT &
tell application "Terminal"
  repeat with w in windows
    repeat with t in tabs of w
      try
        if tty of t is "$my_tty" then
          close w saving no
          return
        end if
      end try
    end repeat
  end repeat
end tell
APPLESCRIPT
