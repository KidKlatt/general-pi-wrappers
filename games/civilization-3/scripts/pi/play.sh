#!/usr/bin/env bash
# play.sh [--x11]: start Civilization III Complete (Conquests). Used by the desktop shortcut.
# Needs no sudo.
#   (default)  Wine's Wayland driver, widescreen (KeepRes=1), Hangover 11.16 with the WowBox64
#              back-end and BOX64_DYNAREC_CALLRET=1. While the game runs the HDMI output is
#              switched to a mode of at least 1024x768 (the game quits without one), 1440x810 if
#              the display offers it, and switched back afterwards.
#   --x11      the same through Xwayland (slower)
# CIV3_MODE=WxH picks the mode yourself (it must be in `wlr-randr`'s list for the display).
# Log: ~/civ3/logs/play-<time>.log
set -u
export CIV3_HOME="${CIV3_HOME:-$(cd "$(dirname "$0")/../.." && pwd)}"   # the game home this script is in
cd "$CIV3_HOME" || exit 2
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
mkdir -p logs
running() { ps -eo comm | grep -q '^Civ3Conquests'; }

# Pick the game's display mode: the first of these the output offers. 1440x810 is the measured
# one (widescreen, fewer pixels than 1080p, so faster); the others keep the map widescreen too.
pick_mode() {
  local modes m
  modes=$(wlr-randr 2>/dev/null | awk '/^[^ ]/{n++} n==1 && $2=="px," {print $1}')
  for m in 1440x810 1600x900 1366x768 1440x900 1280x800 1680x1050 1920x1080 1280x1024 1024x768; do
    if echo "$modes" | grep -qx "$m"; then echo "$m"; return; fi
  done
}

if [ "${1:-}" != --inner ]; then
  LOG="$CIV3_HOME/logs/play-$(date +%Y%m%d-%H%M%S).log"
  if running; then echo "Civilization III is already running." | tee -a "$LOG"; exit 1; fi
  MODE="${CIV3_MODE:-$(pick_mode)}"
  [ -n "$MODE" ] || { echo "No display mode of at least 1024x768 found (wlr-randr); set CIV3_MODE." | tee -a "$LOG"; exit 2; }
  echo "play: display mode $MODE" >>"$LOG"
  exec "$CIV3_HOME/scripts/pi/with-mode.sh" "$MODE" "$0" --inner "$LOG" "$@" >>"$LOG" 2>&1
fi
shift; LOG=$1; shift
X11=0; for a in "$@"; do [ "$a" = --x11 ] && X11=1; done

set -a
. config/pi4-civ3.env
. config/track-hangover.env
set +a
export HODLL=wowbox64.dll BOX64_DYNAREC_CALLRET=1 WINEDEBUG="${WINEDEBUG:--all}"
trap '$WINESERVER_CMD -k' EXIT
cd "$GAME_DIR" || exit 2
echo "play: x11=$X11 HODLL=$HODLL"
if [ "$X11" = 1 ]; then
  DISPLAY="${DISPLAY:-:0}" $WINE_CMD "$GAME_EXE"
else
  env -u DISPLAY $WINE_CMD "$GAME_EXE"
fi
# The loader can return before the game does; wait until the game is gone.
sleep 5
while running; do sleep 2; done
echo "play: game ended"
