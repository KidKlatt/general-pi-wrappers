#!/usr/bin/env bash
# install-cnc-ddraw.sh: put cnc-ddraw (open-source DirectDraw wrapper, MIT) next to the game.
# Source: https://github.com/FunkyFr3sh/cnc-ddraw/releases/download/v7.1.0.0/cnc-ddraw.zip
#   sha256 0b13ab89a64c9918189b1dadd449ef6ed3cb3b7b19cabd96d8adbd95505bb908
# Downloaded once (if missing) and unpacked in $HOME_DIR/tools/cnc-ddraw-7.1.0.0/x; the download
# is refused if the hash differs. Settings: config/cnc-ddraw/ddraw.ini.
# Only the working game folder changes; the .pristine copy is hard-linked, so files are removed
# and re-created, never written in place. The game's own ddraw.dll (GOG's, in Sudden Strike 2) is
# kept as ddraw.dll.gog. Wine only loads this wrapper when WINEDLLOVERRIDES has ddraw=n (play.sh
# does that); without it Wine uses its built-in ddraw as before.
set -eu
HOME_DIR="${SS2_HOME:-$HOME/ss2}"
GAME_DIRS="${GAME_DIRS:-game-ss2}"
URL=https://github.com/FunkyFr3sh/cnc-ddraw/releases/download/v7.1.0.0/cnc-ddraw.zip
SHA=0b13ab89a64c9918189b1dadd449ef6ed3cb3b7b19cabd96d8adbd95505bb908
T="$HOME_DIR/tools/cnc-ddraw-7.1.0.0"; SRC="$T/x"
if [ ! -f "$SRC/ddraw.dll" ]; then
  command -v unzip >/dev/null || { echo "needs unzip (sudo apt install unzip)"; exit 2; }
  mkdir -p "$T"
  [ -f "$T/cnc-ddraw.zip" ] || curl -fL --retry 3 -o "$T/cnc-ddraw.zip" "$URL"
  echo "$SHA  $T/cnc-ddraw.zip" | sha256sum -c - || { rm -f "$T/cnc-ddraw.zip"; exit 2; }
  rm -rf "$SRC"; mkdir -p "$SRC"; unzip -q "$T/cnc-ddraw.zip" -d "$SRC"
fi
[ -f "$SRC/ddraw.dll" ] || { echo "missing $SRC/ddraw.dll"; exit 2; }
for g in $GAME_DIRS; do
  d="$HOME_DIR/$g"
  [ -d "$d" ] || { echo "missing $d"; exit 2; }
  if [ -f "$d/ddraw.dll" ] && ! cmp -s "$d/ddraw.dll" "$SRC/ddraw.dll"; then
    [ -e "$d/ddraw.dll.gog" ] || cp "$d/ddraw.dll" "$d/ddraw.dll.gog"
  fi
  rm -f "$d/ddraw.dll" "$d/ddraw.ini"
  cp "$SRC/ddraw.dll" "$d/ddraw.dll"
  cp "$HOME_DIR/config/cnc-ddraw/ddraw.ini" "$d/ddraw.ini"
  rm -rf "$d/Shaders"; cp -r "$SRC/Shaders" "$d/Shaders"
  echo "$g: cnc-ddraw installed"
done
