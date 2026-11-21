#!/usr/bin/env bash
# uninstall.sh: remove this game from the Pi: its game home (the game, its saves and settings, the
# Wine prefix and everything the setup built there) and the shortcuts the setup installed.
#
#   <game home>/scripts/pi/uninstall.sh            asks before removing anything
#   <game home>/scripts/pi/uninstall.sh --yes      no question (a tool that already asked)
#   <game home>/scripts/pi/uninstall.sh --check    only list what would be removed
#
#   --home DIR   the game home to remove (default: the home this script is in)
#
# Standard wrapper interface (general-pi-wrappers README, "Setup interface"). Exit codes:
# 0 removed (or listed with --check), 1 failed, 2 usage error, 3 needs you (the game is running,
# no confirmation, or DIR is not this game's home). apt packages are never removed: other games
# and programs may use them; the game's README names the ones its setup installed.
# The same file is used by every game: what it removes is read from the game home's game.json.
set -euo pipefail

GAME_HOME=""; YES=0; CHECK=0
usage() { echo "$1" >&2; echo "usage: uninstall.sh [--home DIR] [--yes] [--check]" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --home) [ $# -ge 2 ] || usage "--home needs a folder"; GAME_HOME="$2"; shift 2 ;;
    --yes) YES=1; shift ;;
    --check) CHECK=1; shift ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) usage "unknown option: $1" ;;
  esac
done
needs() { printf '\nNEEDS YOU: %s\n' "$*" >&2; exit 3; }

[ -n "$GAME_HOME" ] || GAME_HOME="$(cd "$(dirname "$0")/../.." && pwd)"
[ -d "$GAME_HOME" ] || needs "no such folder: $GAME_HOME"
GAME_HOME="$(cd "$GAME_HOME" && pwd -P)"

# Only ever remove a folder that is a game home made by a General Pi setup.
case "$GAME_HOME" in
  /|/home|/root|"$(cd "$HOME" && pwd -P)") needs "refusing to remove $GAME_HOME" ;;
esac
[ -f "$GAME_HOME/game.json" ] && [ -d "$GAME_HOME/config" ] && [ -d "$GAME_HOME/scripts/pi" ] ||
  needs "$GAME_HOME does not look like a game home (no game.json, config/ and scripts/pi/); nothing removed."
read -r SLUG TITLE < <(python3 -I -c 'import json,sys; g=json.load(open(sys.argv[1])); print(g["slug"], g["title"])' "$GAME_HOME/game.json") ||
  needs "cannot read $GAME_HOME/game.json; nothing removed."

# Run from a copy outside the folder this removes.
if [ -z "${GPI_UNINSTALL_COPY:-}" ]; then
  copy="$(mktemp "${TMPDIR:-/tmp}/gpi-uninstall.XXXXXX")"
  cp "$0" "$copy"
  args=(--home "$GAME_HOME"); [ "$YES" = 1 ] && args+=(--yes); [ "$CHECK" = 1 ] && args+=(--check)
  GPI_UNINSTALL_COPY="$copy" exec bash "$copy" "${args[@]}"
fi
trap 'rm -f "$GPI_UNINSTALL_COPY"' EXIT

# Is anything of this game running? Every General Pi game keeps its Wine prefix in its home, and
# every Wine process carries WINEPREFIX in its environment.
running=""
for p in /proc/[0-9]*; do
  e=$({ tr '\0' '\n' < "$p/environ"; } 2>/dev/null | sed -n 's/^WINEPREFIX=//p' | head -1) || true
  [ -n "$e" ] || continue
  e=$(readlink -m "$e" 2>/dev/null || echo "$e")   # same spelling as GAME_HOME (symlinks resolved)
  case "$e/" in "$GAME_HOME"/*) running="$running ${p#/proc/}" ;; esac
done
[ -z "$running" ] || needs "$TITLE is still running (process$running). Close it, wait a few seconds and try again."

# The shortcuts the setup installed: same file names as config/desktop/, pointing into this home.
shortcuts=()
for f in "$GAME_HOME"/config/desktop/*.desktop; do
  [ -e "$f" ] || continue
  for d in "$HOME/.local/share/applications" "$HOME/Desktop"; do
    s="$d/$(basename "$f")"
    [ -f "$s" ] && grep -qF "$GAME_HOME/" "$s" && shortcuts+=("$s")
  done
done

SIZE=$(du -sh "$GAME_HOME" 2>/dev/null | cut -f1)
echo "$TITLE ($SLUG). This removes:"
echo "  $GAME_HOME  ($SIZE: the game with its saves and settings, the Wine prefix, downloads, logs)"
for s in "${shortcuts[@]}"; do echo "  $s"; done
echo "Not removed: apt packages (other games and programs may use them; see the game's README)."
[ "$CHECK" = 0 ] || exit 0

if [ "$YES" != 1 ]; then
  [ -t 0 ] || needs "not removed: confirm by running it in a terminal, or add --yes."
  printf 'Type yes to remove it: '; read -r answer
  [ "$answer" = yes ] || needs "not removed (you did not type yes)."
fi

for s in "${shortcuts[@]}"; do rm -f "$s"; done
rm -rf "$GAME_HOME" || { echo "ERROR: could not remove all of $GAME_HOME" >&2; exit 1; }
echo "Removed $TITLE."
