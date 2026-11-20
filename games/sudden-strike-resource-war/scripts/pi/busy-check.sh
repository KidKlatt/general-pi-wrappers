#!/usr/bin/env bash
# Refuse to start a Wine program for this project while another project's Wine is running.
#
#   busy-check.sh            exit 0 if no other project's wineserver runs, else list them, exit 1
#   busy-check.sh --list     list every running wineserver and the prefix it serves, exit 0
#
# Several game projects share the Pi, each in ~/<short_id> with its own Wine prefixes. Two games
# at once on a 4 GB Pi starve each other and make any measurement worthless. Each prefix runs its
# own wineserver, which carries WINEPREFIX in its environment, so the owner of every running Wine
# is the first folder under $HOME in that prefix path (~/mtw/..., ~/ss2/..., ~/stw/...).
# Read-only: it never stops anything. Stopping another project's game is the human's call.
set -u
ME=ssrw

list() {
  for pid in $(pgrep wineserver 2>/dev/null | sort -u); do
    [ -r "/proc/$pid/environ" ] || continue
    pfx=$(tr '\0' '\n' <"/proc/$pid/environ" 2>/dev/null | sed -n 's/^WINEPREFIX=//p' | head -1)
    [ -n "$pfx" ] || pfx="$HOME/.wine"
    case "$pfx" in
      "$HOME"/*/*) owner=${pfx#"$HOME"/}; owner=${owner%%/*} ;;
      *) owner=other ;;
    esac
    echo "wineserver pid $pid owner=$owner prefix=$pfx"
  done
}

OUT=$(list)
[ -n "$OUT" ] && echo "$OUT" >&2
[ "${1:-}" = "--list" ] && exit 0
if [ -n "$OUT" ] && echo "$OUT" | grep -qv "owner=$ME "; then
  echo "BUSY: another project's Wine is running (listed above). Ask the human to close that game; never kill it." >&2
  exit 1
fi
exit 0
