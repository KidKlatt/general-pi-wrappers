#!/usr/bin/env bash
# play.sh [--fps] [--window]: start Shogun: Total War for play (Track B: Box64 + this project's own
# Wine 9.17 with the rebuilt winex11.so, game-lazy copy with the d3d9lazy shim and the
# linear-resampler dsound.dll). Used by the desktop shortcuts in config/desktop.
#   --fps      show Mesa's frame-rate counter in the top left corner
#   --window   the game in an 800x600 Wine desktop window (profile-best, as the test harness runs)
# Default is full screen (profile-final-pi4 = profile-10-fullscreen, experiment 58): no Wine desktop; this project's
# winex11.so turns the game's 800x600 / 640x480 modes into Xwayland emulated modes, and Xwayland
# scales the game to the whole screen (stretched to 16:9). Nothing in the registry changes, and
# the screen mode is untouched for every other program; it ends when the game exits.
# Needs no sudo. Refuses to start if Shogun already runs.
set -u
STW_HOME="${STW_HOME:-$HOME/stw}"
cd "$STW_HOME" || exit 2
FPS=0
PROFILE=config/profile-final-pi4.env
for a in "$@"; do
  case "$a" in
    --fps) FPS=1 ;;
    --window) PROFILE=config/profile-best.env ;;
  esac
done

mkdir -p logs
LOG="$STW_HOME/logs/play-$(date +%Y%m%d-%H%M%S).log"

msg() { # message to the log and a desktop pop-up
  echo "$1" | tee -a "$LOG"
  command -v zenity >/dev/null && DISPLAY="${DISPLAY:-:0}" zenity --warning --no-wrap --text="$1" 2>/dev/null &
}

if pgrep -x ShogunM.exe >/dev/null; then
  msg "Shogun: Total War is already running."
  exit 1
fi

set -a
. config/pi4-stw-lazy.env
. config/track-box64.env
. "$PROFILE"
set +a
export DISPLAY="${DISPLAY:-${DISPLAY_NUM:-:0}}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export WINEPREFIX WINEDEBUG="${WINEDEBUG:-fixme-all}"
unset GALLIUM_HUD
[ "$FPS" = 1 ] && export GALLIUM_HUD=fps
echo "play.sh fps=$FPS track=$TRACK_VERSION profile=$PROFILE" >>"$LOG"

G="$STW_HOME/$GAME_DIR"
# Leftover test switches and the shim's statistics log from earlier runs.
rm -f "$G"/d3d9lazy.no* "$G"/d3d9lazy.depth* "$G"/d3d9lazy.dips
: > "$G/d3d9lazy.log"

trap '$WINESERVER_CMD -k >>"$LOG" 2>&1' EXIT

cd "$G" || exit 2
# WINE_CMD and GAME_ARGS are intentionally word-split.
if [ -n "${VDESK:-}" ]; then
  $WINE_CMD explorer "/desktop=STW,$VDESK" "$GAME_EXE" ${GAME_ARGS:-} >>"$LOG" 2>&1
else
  $WINE_CMD "$GAME_EXE" ${GAME_ARGS:-} >>"$LOG" 2>&1
fi
# explorer can return before the game does; wait until the game is gone.
while pgrep -x ShogunM.exe >/dev/null; do sleep 2; done
