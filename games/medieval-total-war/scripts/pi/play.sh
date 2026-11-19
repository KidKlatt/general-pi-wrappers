#!/usr/bin/env bash
# play.sh [--fps] [--window]: start Medieval: Total War (Track A / Hangover, game-lazy copy with
# the d3d9lazy shim). Used by the desktop shortcuts.
#   --fps      show Mesa's frame-rate counter in the top left corner
#   --window   the old way: unscaled game in the corner of a 1024x768 Wine desktop window
#              (profile 42, the configuration the tests were validated with)
# Default is full screen (profile 43: no Wine virtual desktop). Wine then scales the game's
# picture to the display, keeping its shape; this needs the prefix setting
# HKCU\Software\Wine\X11 Driver\EmulateModeset=Y (set 2026-11-15, experiment 133).
# The battle resolution is chosen in the game: Options > Video.
# This script needs no sudo. On a Pi that also runs heavy background jobs, see "Known limits"
# in docs/NEW-PI-SETUP.md.
set -u
MTW_HOME="${MTW_HOME:-$HOME/mtw}"
cd "$MTW_HOME" || exit 2
PROFILE=config/profile-43-hangover-d3d9lazy-fullscreen.env
FPS=0
for a in "$@"; do
  case "$a" in
    --fps) FPS=1 ;;
    --window) PROFILE=config/profile-42-hangover-d3d9lazy-vram512.env ;;
  esac
done

set -a
. config/pi4-lazy.env
. config/track-hangover.env
. "$PROFILE"
set +a
export DISPLAY="${DISPLAY:-${DISPLAY_NUM:-:0}}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export WINEPREFIX WINEDEBUG="${WINEDEBUG:-fixme-all}"
[ "$FPS" = 1 ] && export GALLIUM_HUD=fps

mkdir -p logs
LOG="logs/play-$(date +%Y%m%d-%H%M%S).log"

if ps -eo comm | grep -q '^Medieval_TW'; then
  echo "The game is already running." | tee -a "$LOG"
  exit 1
fi

# Leftover test switches and the shim's statistics log from earlier runs.
rm -f "$GAME_DIR"/d3d9lazy.no* "$GAME_DIR"/d3d9lazy.depth* "$GAME_DIR"/d3d9lazy.dips
: > "$GAME_DIR/d3d9lazy.log"

G="$MTW_HOME/$GAME_DIR"
if [ -n "${VDESK:-}" ]; then MODE=window; else MODE=fullscreen; fi
REGKEY='HKCU\Software\Wine\X11 Driver'

# The game stores the chosen resolutions as positions in the list of display modes, and that list
# differs between the two ways of running. Each way therefore keeps its own copy of the game's
# settings file (Medieval.Cfg.fullscreen / Medieval.Cfg.window). Between runs Medieval.Cfg is the
# window copy, because the test harness (run-test.sh) runs in a Wine desktop window.
[ -f "$G/Medieval.Cfg.$MODE" ] && cp -p "$G/Medieval.Cfg.$MODE" "$G/Medieval.Cfg"

# EmulateModeset=Y makes Wine scale the full-screen picture, but it breaks the Wine desktop window
# (black 640x480 window, "display settings returned -2"), so it is set only while a full-screen
# game runs and removed again afterwards.
if [ "$MODE" = fullscreen ]; then
  $WINE_CMD reg add "$REGKEY" /v EmulateModeset /t REG_SZ /d Y /f >>"$LOG" 2>&1
else
  $WINE_CMD reg delete "$REGKEY" /v EmulateModeset /f >>"$LOG" 2>&1
fi
$WINESERVER_CMD -w

restore() {
  cp -p "$G/Medieval.Cfg" "$G/Medieval.Cfg.$MODE"
  [ -f "$G/Medieval.Cfg.window" ] && cp -p "$G/Medieval.Cfg.window" "$G/Medieval.Cfg"
  $WINE_CMD reg delete "$REGKEY" /v EmulateModeset /f >>"$MTW_HOME/$LOG" 2>&1
  $WINESERVER_CMD -k >>"$MTW_HOME/$LOG" 2>&1
}
trap restore EXIT

cd "$GAME_DIR" || exit 2
# WINE_CMD and GAME_ARGS are intentionally word-split.
if [ -n "${VDESK:-}" ]; then
  $WINE_CMD explorer "/desktop=MTW,$VDESK" "$GAME_EXE" ${GAME_ARGS:-} >>"$MTW_HOME/$LOG" 2>&1
else
  $WINE_CMD "$GAME_EXE" ${GAME_ARGS:-} >>"$MTW_HOME/$LOG" 2>&1
fi
# explorer can return before the game does; wait until the game is gone.
while ps -eo comm | grep -q '^Medieval_TW'; do sleep 2; done
