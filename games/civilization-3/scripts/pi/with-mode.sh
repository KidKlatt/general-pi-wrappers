#!/usr/bin/env bash
# with-mode.sh <WxH> <command...>
# Switch the Pi's HDMI output to a taller mode while one command runs, then restore the mode
# that was set before, even if the command fails or is interrupted. Civilization III quits
# silently when no display mode of at least 1024x768 exists (experiment 12); the human approved
# switching to 1440x810 while the game runs (2026-11-19). Only the output mode changes; nothing
# is written to labwc's config, so a reboot or logout always comes back at the saved mode.
set -u
[ $# -ge 2 ] || { echo "usage: with-mode.sh <WxH> <command...>"; exit 2; }
MODE=$1; shift
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
OUT=${CIV3_OUTPUT:-$(wlr-randr | awk '/^[^ ]/{o=$1} /Enabled: yes/{print o; exit}')}
[ -n "$OUT" ] || { echo "with-mode: no enabled output found"; exit 2; }
# wlr-randr marks the mode "(current)" or, when it is also the preferred one, "(preferred, current)"
OLD=$(wlr-randr | awk -v o="$OUT" '$1==o{f=1;next} /^[^ ]/{f=0} f&&/[(, ]current\)/{print $1; exit}')
[ -n "$OLD" ] || { echo "with-mode: cannot read the current mode of $OUT"; exit 2; }
restore() {
  wlr-randr --output "$OUT" --mode "$OLD" && echo "with-mode: $OUT restored to $OLD"
}
trap restore EXIT
trap 'exit 130' INT TERM HUP
if [ "$MODE" != "$OLD" ]; then
  wlr-randr --output "$OUT" --mode "$MODE" || { echo "with-mode: $MODE not accepted"; exit 2; }
  echo "with-mode: $OUT $OLD -> $MODE"
  sleep 2   # let Xwayland pick up the new size
fi
"$@"
