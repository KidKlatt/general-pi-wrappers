#!/usr/bin/env bash
# setup.sh: set up Sid Meier's Civilization III Complete (GOG) on a Raspberry Pi, the same way as
# the working Pi 4: Hangover 11.16 with its WowBox64 back-end, Wine's Wayland driver, widescreen.
# Run it ON THE PI from a copy of this folder (any place), as your normal user:
#
#   scripts/pi/setup.sh --installer ~/gog
#
#   --installer DIR   folder holding your GOG offline installer setup_civilization3_complete_*.exe
#   --home DIR        where the game is set up (default ~/civ3)
#   --allow-upgrades  continue even if apt wants to upgrade or remove installed packages
#                     (default: stop, so a Pi that also runs a server is not changed by surprise)
#   --no-desktop      do not install the desktop shortcut
#
# Steps: checks; apt packages (innoextract, wlr-randr; Hangover 11.16 from its official release if
# missing); copies the scripts and config into the game home; extracts the installer; applies the
# files GOG's installer drops into place (__support/save); writes conquests.ini; creates the Wine
# prefix with the game's registry keys; installs the desktop shortcut. Each step leaves a marker in
# <home>/.setup/, so a second run resumes; delete a marker to redo a step. Uses sudo only for apt.
# Nothing outside the game home is changed except apt packages and the shortcut.
set -euo pipefail

INSTALLER_DIR=""; CIV3_HOME="$HOME/civ3"; ALLOW_UPGRADES=0; DESKTOP=1
while [ $# -gt 0 ]; do
  case "$1" in
    --installer) INSTALLER_DIR="$2"; shift 2 ;;
    --home) CIV3_HOME="$2"; shift 2 ;;
    --allow-upgrades) ALLOW_UPGRADES=1; shift ;;
    --no-desktop) DESKTOP=0; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

SRC="$(cd "$(dirname "$0")/../.." && pwd)"
CIV3_HOME="$(mkdir -p "$CIV3_HOME" && cd "$CIV3_HOME" && pwd)"
MARK="$CIV3_HOME/.setup"
mkdir -p "$MARK" "$CIV3_HOME/logs" "$CIV3_HOME/downloads" "$CIV3_HOME/prefixes"
LOG="$CIV3_HOME/logs/setup-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

# Pinned: what the working Pi uses. Hangover checksum from its official release page.
HANGOVER_VER=11.16
HANGOVER_TAR="hangover_${HANGOVER_VER}_debian13_trixie_arm64.tar"
HANGOVER_URL="https://github.com/AndreRH/hangover/releases/download/hangover-${HANGOVER_VER}/${HANGOVER_TAR}"
HANGOVER_SHA=b5493f5903ab3c05f78bf4c03b06ac0005eb26f732437748c1592fefa45e861a
# GOG offline installer tested (2.0.0.7). Another build may work; the script only warns.
GOG_SHA=4ad54ca308ea93af49b0db3a795736eda91aed61c8cd73b18196802d0f4d2395

say()   { echo; echo "=== $*"; }
die()   { echo "ERROR: $*" >&2; exit 1; }
done_() { [ -f "$MARK/$1.done" ]; }
mark()  { touch "$MARK/$1.done"; }

# apt with a dry run first: stop if anything installed would be upgraded or removed.
apt_install() {
  local sim
  sim=$(sudo apt-get -s install --no-install-recommends "$@") || die "apt-get -s install $* failed"
  if echo "$sim" | grep -qE '^(Remv|Inst [^ ]+ \[)'; then
    echo "$sim" | grep -E '^(Remv|Inst [^ ]+ \[)'
    [ "$ALLOW_UPGRADES" = 1 ] || die "apt would upgrade or remove the packages above. Check them, then rerun with --allow-upgrades if that is fine."
  fi
  sudo apt-get install -y --no-install-recommends "$@"
}

say "1/7 Checks"
[ "$(uname -m)" = aarch64 ] || die "needs 64-bit Raspberry Pi OS (aarch64); this is $(uname -m)."
. /etc/os-release
[ "${VERSION_CODENAME:-}" = trixie ] || die "needs Raspberry Pi OS / Debian 13 'trixie' (Hangover's package is built for it); this is ${PRETTY_NAME:-unknown}."
[ "$(getconf PAGESIZE)" = 4096 ] || die "the kernel uses $(getconf PAGESIZE)-byte pages; Hangover needs 4 KB pages. On a Pi 5 add 'kernel=kernel8.img' to /boot/firmware/config.txt and reboot."
[ -n "$INSTALLER_DIR" ] || die "give the folder with your GOG installer: --installer DIR"
INSTALLER=$(ls "$INSTALLER_DIR"/setup_civilization3_complete_*.exe 2>/dev/null | head -1)
[ -n "$INSTALLER" ] || die "no setup_civilization3_complete_*.exe in $INSTALLER_DIR"
FREE=$(df -Pk "$CIV3_HOME" | awk 'NR==2{print $4}')
[ "$FREE" -gt 5000000 ] || done_ extract || die "needs about 5 GB free in $CIV3_HOME (game 1.8 GB, Wine prefix 2.3 GB)"
echo "installer: $INSTALLER"; echo "game home: $CIV3_HOME"

say "2/7 Packages"
if ! done_ packages; then
  need=()
  for p in innoextract wlr-randr; do dpkg -s "$p" >/dev/null 2>&1 || need+=("$p"); done
  if [ ${#need[@]} -gt 0 ]; then apt_install "${need[@]}"; else echo "innoextract and wlr-randr are installed."; fi
  if dpkg -s hangover-wine >/dev/null 2>&1 && dpkg -s hangover-wowbox64 >/dev/null 2>&1; then
    echo "Hangover: $(dpkg-query -W -f='${Version}' hangover-wine) with WowBox64 is installed."
    case "$(dpkg-query -W -f='${Version}' hangover-wine)" in
      "$HANGOVER_VER"*) ;; *) echo "NOTE: tested with Hangover $HANGOVER_VER; this Pi has another version." ;;
    esac
  else
    cd "$CIV3_HOME/downloads"
    if [ ! -f "$HANGOVER_TAR" ]; then
      wget -q --show-progress -O "$HANGOVER_TAR.part" "$HANGOVER_URL" && mv -f "$HANGOVER_TAR.part" "$HANGOVER_TAR"
    fi
    echo "$HANGOVER_SHA  $HANGOVER_TAR" | sha256sum -c - || die "Hangover download checksum mismatch; delete $CIV3_HOME/downloads/$HANGOVER_TAR and retry."
    mkdir -p "hangover-$HANGOVER_VER" && tar -xf "$HANGOVER_TAR" -C "hangover-$HANGOVER_VER"
    H="$CIV3_HOME/downloads/hangover-$HANGOVER_VER"
    apt_install "$H"/hangover-wine_*_arm64.deb "$H"/hangover-wowbox64_*_arm64.deb
  fi
  mark packages
fi

say "3/7 Scripts and config into $CIV3_HOME"
if [ "$SRC" != "$CIV3_HOME" ]; then
  mkdir -p "$CIV3_HOME/scripts/pi" "$CIV3_HOME/config"
  cp -f "$SRC"/scripts/pi/*.sh "$CIV3_HOME/scripts/pi/"
  cp -rf "$SRC"/config/. "$CIV3_HOME/config/"
fi
chmod +x "$CIV3_HOME"/scripts/pi/*.sh
echo "done"

say "4/7 Extracting the game (about 2-3 minutes)"
if ! done_ extract; then
  if [ "$(sha256sum "$INSTALLER" | cut -d' ' -f1)" != "$GOG_SHA" ]; then
    echo "NOTE: this installer is not the tested build 2.0.0.7 (SHA-256 differs); continuing."
  fi
  rm -rf "$CIV3_HOME/game.x" "$CIV3_HOME/game"
  innoextract --gog --progress=0 -d "$CIV3_HOME/game.x" "$INSTALLER"
  mv "$CIV3_HOME/game.x/app" "$CIV3_HOME/game"
  rm -rf "$CIV3_HOME/game.x"
  [ -f "$CIV3_HOME/game/Conquests/Civ3Conquests.exe" ] || die "Conquests/Civ3Conquests.exe missing after extraction"
  mark extract
fi
echo "game in $CIV3_HOME/game"

say "5/7 GOG support files and conquests.ini"
G="$CIV3_HOME/game"
# GOG's installer copies __support/save over the game (Lucida Sans font, Conquests rules files).
(cd "$G/__support/save" && find . -type f) | while read -r f; do
  mkdir -p "$G/$(dirname "$f")"; cp -n "$G/__support/save/$f" "$G/$f"
done
# KeepRes=1: keep the desktop mode (widescreen map); PlayIntro=0: skip the Bink intro, whose
# 640x480 mode switch breaks the window under Wine's Wayland driver. The game reads [Conquests].
INI="$G/Conquests/conquests.ini"
if [ ! -f "$INI" ]; then
  cp "$CIV3_HOME/config/game/conquests.ini" "$INI"
else
  for k in KeepRes=1 PlayIntro=0; do
    grep -q "^${k%%=*}=" "$INI" || sed -i "/^\[Conquests\]/a $k" "$INI"
    sed -i "s/^${k%%=*}=.*/$k/" "$INI"
  done
fi
echo "done"

say "6/7 Wine prefix and registry keys"
export CIV3_HOME
set -a; . "$CIV3_HOME/config/track-hangover.env"; set +a
export WINEPREFIX="$CIV3_HOME/prefixes/hangover" HODLL=wowbox64.dll WINEDEBUG=-all WINEDLLOVERRIDES="mscoree=;mshtml="
if ! done_ prefix; then
  env -u DISPLAY $WINE_CMD wineboot -i
  $WINESERVER_CMD -w
  mark prefix
fi
WG="Z:$(echo "$G" | tr '/' '\\')"
$WINE_CMD reg add 'HKLM\SOFTWARE\Infogrames Interactive\Civilization III' /v Install_Path /t REG_SZ /d "$WG" /f /reg:32
$WINE_CMD reg add 'HKLM\SOFTWARE\Infogrames\Civ3PTW' /v Install_Path /t REG_SZ /d "$WG\\civ3PTW" /f /reg:32
$WINE_CMD reg add 'HKCU\Software\Wine\WineDbg' /v ShowCrashDialog /t REG_DWORD /d 0 /f
$WINESERVER_CMD -w

say "7/7 Desktop shortcut"
if [ "$DESKTOP" = 1 ]; then
  D="$HOME/Desktop/Civilization-III.desktop"
  mkdir -p "$HOME/Desktop" "$HOME/.local/share/applications"
  sed "s#^Exec=.*#Exec=env CIV3_HOME=$CIV3_HOME $CIV3_HOME/scripts/pi/play.sh#" \
      "$CIV3_HOME/config/desktop/Civilization-III.desktop" > "$D"
  chmod +x "$D"
  cp "$D" "$HOME/.local/share/applications/"
  echo "shortcut: $D (and the Games menu)"
else
  echo "skipped (--no-desktop)"
fi

say "Done. Start the game with the 'Civilization III' shortcut or: $CIV3_HOME/scripts/pi/play.sh"
