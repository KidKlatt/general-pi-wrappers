#!/usr/bin/env bash
# Refuse to start a Wine program for this project while another project's Wine is running.
#
#   busy-check.sh            exit 0 if no other project's wineserver runs, else list them, exit 1
#   busy-check.sh --list     list every running wineserver and the prefix it serves, exit 0
#
# Three game projects share this Pi (Medieval: Total War in ~/mtw, Sudden Strike in ~/ss2, and
# this one in ~/stw). Each has its own Wine prefix, so they cannot overwrite each other's files,
# but two games at once on a 4 GB Pi that also serves IIAB would starve each other and make any
# measurement worthless. Each prefix runs its own wineserver, which carries WINEPREFIX in its
# environment, so the owner of every running Wine can be told apart.
# Read-only: it never stops anything. Stopping another project's game is the human's call.
set -u
STW_HOME="${STW_HOME:-$HOME/stw}"

list() {
  for pid in $(pgrep wineserver 2>/dev/null | sort -u); do
    [ -r "/proc/$pid/environ" ] || continue
    pfx=$(tr '\0' '\n' <"/proc/$pid/environ" 2>/dev/null | sed -n 's/^WINEPREFIX=//p' | head -1)
    [ -n "$pfx" ] || pfx="$HOME/.wine"
    case "$pfx" in
      "$STW_HOME"/*) owner=stw ;;
      "$HOME/mtw"/*) owner=mtw ;;
      "$HOME/ss2"/*) owner=ss2 ;;
      *) owner=other ;;
    esac
    echo "wineserver pid $pid owner=$owner prefix=$pfx"
  done
}

OUT=$(list)
[ -n "$OUT" ] && echo "$OUT" >&2
[ "${1:-}" = "--list" ] && exit 0
if echo "$OUT" | grep -q 'owner=' && echo "$OUT" | grep -qv 'owner=stw'; then
  echo "BUSY: another project's Wine is running (listed above). Ask the human to close that game; never kill it." >&2
  exit 1
fi
exit 0
