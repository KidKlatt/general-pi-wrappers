#!/usr/bin/env bash
# install-cnc-ddraw.sh: put cnc-ddraw (open-source DirectDraw wrapper, MIT) next to both games.
# Source: https://github.com/FunkyFr3sh/cnc-ddraw/releases/download/v7.1.0.0/cnc-ddraw.zip
#   sha256 0b13ab89a64c9918189b1dadd449ef6ed3cb3b7b19cabd96d8adbd95505bb908
# Unpacked in ~/ss2/tools/cnc-ddraw-7.1.0.0/x. Settings: config/cnc-ddraw/ddraw.ini.
# Only the working game folders change; the .pristine copies are hard links, so files are
# removed and re-created, never written in place. Sudden Strike 2's GOG ddraw.dll is kept as
# ddraw.dll.gog. Wine only loads this wrapper when WINEDLLOVERRIDES has ddraw=n (play.sh does
# that); without it Wine uses its built-in ddraw as before.
set -eu
SS2_HOME="${SS2_HOME:-$HOME/ss2}"
SRC="$SS2_HOME/tools/cnc-ddraw-7.1.0.0/x"
[ -f "$SRC/ddraw.dll" ] || { echo "missing $SRC/ddraw.dll"; exit 2; }
for g in game-ss2 game-rw; do
  d="$SS2_HOME/$g"
  if [ -f "$d/ddraw.dll" ] && ! cmp -s "$d/ddraw.dll" "$SRC/ddraw.dll"; then
    [ -e "$d/ddraw.dll.gog" ] || cp "$d/ddraw.dll" "$d/ddraw.dll.gog"
  fi
  rm -f "$d/ddraw.dll" "$d/ddraw.ini"
  cp "$SRC/ddraw.dll" "$d/ddraw.dll"
  cp "$SS2_HOME/config/cnc-ddraw/ddraw.ini" "$d/ddraw.ini"
  rm -rf "$d/Shaders"; cp -r "$SRC/Shaders" "$d/Shaders"
  echo "$g: cnc-ddraw installed"
done
