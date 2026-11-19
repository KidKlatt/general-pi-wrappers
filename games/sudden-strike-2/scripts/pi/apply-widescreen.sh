#!/usr/bin/env bash
# apply-widescreen.sh install|remove: switch Sudden Strike 2 (game-ss2) to the 16:9 resolution
# made by St1cky's SS2 Multi Resolution Patcher v1.4.0 (closed source; run only inside
# scripts/pi/sandbox.sh on copies, approved by the human 2026-11-17).
# Patched files live in ~/ss2/widescreen/<WxH>/ (default 1280x720):
#   n2Cad1024.dll            patcher output (base: GOG original, sha256 3eebe8ac...)
#   n2Game_Dll.dll           patcher output + GOG's 2-byte music change (import WINMM.dll ->
#                            WIN32.dll at file offset 0xf6b87), so the Ogg music wrapper still works
# The patch replaces the game's 1024x768 mode, so VideoMode=3 = the new resolution.
# Files are removed and re-created (never written in place: game-ss2.pristine is hard-linked).
set -eu
SS2_HOME="${SS2_HOME:-$HOME/ss2}"; RES="${RES:-1280x720}"
G="$SS2_HOME/game-ss2"; W="$SS2_HOME/widescreen/$RES"; B="$SS2_HOME/widescreen/backup-installed"
# cnc-ddraw: with a 16:9 battlefield, keep proportions (menus/videos stay 4:3 with bars).
setaspect() { local t; t="$(mktemp)"; sed "s/^maintas=.*/maintas=$1/" "$G/ddraw.ini" > "$t"; rm -f "$G/ddraw.ini"; cp "$t" "$G/ddraw.ini"; rm -f "$t"; }
setmode() { local t; t="$(mktemp)"; sed "s/^VideoMode=.*/VideoMode=$1\r/" "$G/sudtest.ini" | sed 's/\r\r/\r/' > "$t"; rm -f "$G/sudtest.ini"; cp "$t" "$G/sudtest.ini"; rm -f "$t"; }
case "${1:-}" in
  install)
    [ -f "$W/n2Cad1024.dll" ] && [ -f "$W/n2Game_Dll.dll" ] || { echo "missing $W"; exit 2; }
    mkdir -p "$B"
    for f in n2Cad1024.dll n2Game_Dll.dll; do [ -e "$B/$f" ] || cp "$G/$f" "$B/$f"; done
    for f in n2Cad1024.dll n2Game_Dll.dll; do rm -f "$G/$f"; cp "$W/$f" "$G/$f"; done
    setmode 3; [ -f "$G/ddraw.ini" ] && setaspect true; echo "installed $RES; VideoMode=3; maintas=true" ;;
  remove)
    for f in n2Cad1024.dll n2Game_Dll.dll; do rm -f "$G/$f"; cp "$B/$f" "$G/$f"; done
    setmode 2; [ -f "$G/ddraw.ini" ] && setaspect false; echo "restored 4:3 files; VideoMode=2; maintas=false" ;;
  *) echo "usage: apply-widescreen.sh install|remove"; exit 2 ;;
esac
grep -a '^VideoMode' "$G/sudtest.ini"; sha256sum "$G/n2Cad1024.dll" "$G/n2Game_Dll.dll"
