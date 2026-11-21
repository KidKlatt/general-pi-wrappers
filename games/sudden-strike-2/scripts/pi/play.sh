#!/usr/bin/env bash
# play.sh [--fps] [--fit|--window]: start Sudden Strike 2 (Hangover).
# Used by the desktop shortcut. Needs no sudo. Resource War is its own project since 2026-11-20
# (~/ssrw, projects/sudden-strike-resource-war). A leading "ss2" (old shortcuts) is ignored.
#   (default)  full screen, picture stretched to fill the whole display, whatever its size and
#              shape (no side bars on 16:9). Uses cnc-ddraw (scripts/pi/install-cnc-ddraw.sh,
#              settings config/cnc-ddraw/ddraw.ini) as a borderless window; no mode change.
#   --fit      full screen keeping the game's 4:3 shape (side bars on a 16:9 display): Wine's
#              built-in ddraw, the game switches mode and Wine scales it. Needs the prefix setting
#              HKCU\Software\Wine\X11 Driver\EmulateModeset=Y, which breaks Wine desktop windows
#              (and so the test harness), so it is set only while the game runs.
#   --window   Wine desktop window of the game's size (Wine's built-in ddraw)
#   --fps      show Mesa's frame-rate counter in the top left corner
# The game's own resolution is sudtest.ini VideoMode: 1=640x480, 2=800x600, 3=1024x768 (all 4:3).
set -u
SS2_HOME="${SS2_HOME:-$HOME/ss2}"
cd "$SS2_HOME" || exit 2
GAME=ss2
case "${1:-}" in
  ss2) shift ;;
  rw) echo "Resource War moved to its own folder: ~/ssrw/scripts/pi/play.sh"; exit 2 ;;
esac
FPS=0; MODE=stretch
for a in "$@"; do
  case "$a" in
    --fps) FPS=1 ;; --fit) MODE=fit ;; --window) MODE=window ;;
    *) echo "usage: play.sh [--fps] [--fit|--window]"; exit 2 ;;
  esac
done
set -a
. "config/pi4-$GAME.env"
. config/track-hangover.env
. config/profile-play.env
set +a
export DISPLAY="${DISPLAY:-${DISPLAY_NUM:-:0}}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export WINEPREFIX WINEDEBUG="${WINEDEBUG:-fixme-all}"
[ "$FPS" = 1 ] && export GALLIUM_HUD=fps

mkdir -p logs
LOG="$SS2_HOME/logs/play-$GAME-$(date +%Y%m%d-%H%M%S).log"
# Sudden Strike 2 and Resource War both run game_exe.exe; started() looks for this game's own copy
# (its Wine prefix), so one does not block the other. running() is any copy, for the wait at the end.
running() { ps -eo comm | grep -q '^game_exe'; }
started() {
  local p
  for p in $(pgrep '^game_exe'); do
    tr '\0' '\n' <"/proc/$p/environ" 2>/dev/null | grep -qxF "WINEPREFIX=$WINEPREFIX" && return 0
  done
  return 1
}
if started; then echo "Sudden Strike 2 is already running." | tee -a "$LOG"; exit 1; fi

if [ "$MODE" = stretch ] && ! grep -q cnc-ddraw "$GAME_DIR/ddraw.ini" 2>/dev/null; then
  echo "cnc-ddraw not installed in $GAME_DIR, using --fit" | tee -a "$LOG"; MODE=fit
fi
echo "mode=$MODE" >>"$LOG"

REGKEY='HKCU\Software\Wine\X11 Driver'
if [ "$MODE" = fit ]; then
  $WINE_CMD reg add "$REGKEY" /v EmulateModeset /t REG_SZ /d Y /f >>"$LOG" 2>&1
else
  $WINE_CMD reg delete "$REGKEY" /v EmulateModeset /f >>"$LOG" 2>&1
fi
$WINESERVER_CMD -w

restore() {
  $WINE_CMD reg delete "$REGKEY" /v EmulateModeset /f >>"$LOG" 2>&1
  $WINESERVER_CMD -k >>"$LOG" 2>&1
}
trap restore EXIT

cd "$GAME_DIR" || exit 2
case "$MODE" in
  stretch)
    WINEDLLOVERRIDES="ddraw=n,b${WINEDLLOVERRIDES:+;$WINEDLLOVERRIDES}" $WINE_CMD "$GAME_EXE" >>"$LOG" 2>&1 ;;
  window)
    case "$(tr -d '\r' < sudtest.ini | sed -n 's/^VideoMode=//p' | head -1)" in
      1) SIZE=640x480 ;; 3) SIZE=1024x768 ;; *) SIZE=800x600 ;;
    esac
    WINEDLLOVERRIDES="ddraw=b" $WINE_CMD explorer "/desktop=SS2,$SIZE" "$GAME_EXE" >>"$LOG" 2>&1 ;;
  fit)
    WINEDLLOVERRIDES="ddraw=b" $WINE_CMD "$GAME_EXE" >>"$LOG" 2>&1 ;;
esac
# The loader or explorer can return before the game does; wait until the game is gone.
sleep 5
while running; do sleep 2; done
