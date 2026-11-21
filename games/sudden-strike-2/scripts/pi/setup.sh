#!/usr/bin/env bash
# setup.sh: set up Sudden Strike 2 (GOG) on a Raspberry Pi, the same way as the working Pi 4:
# Hangover 11.16 with its FEX back-end (libwow64fex), cnc-ddraw for the stretched full screen.
# Run it ON THE PI from a copy of this folder (any place), as your normal user:
#
#   scripts/pi/setup.sh --installer ~/gog
#
#   --installer DIR   folder holding your GOG offline installer setup_sudden_strike_2_*.exe
#   --home DIR        where the game is set up (default ~/ss2)
#   --allow-upgrades  continue even if apt wants to upgrade or remove installed packages
#                     (default: stop, so a Pi that also runs a server is not changed by surprise)
#   --no-desktop      do not install the shortcut (desktop and app menu)
#   --jobs N          accepted for the standard interface; nothing is built for this game
#   --check           only check this Pi and the installer, change nothing
#
# Standard wrapper interface (general-pi-wrappers README, "Setup interface"). Exit codes:
# 0 done, 1 failed (run again to resume), 2 usage error, 3 needs you (fix what it says, rerun).
# Steps: checks; copies the scripts and config into the game home; apt packages (innoextract,
# unzip, curl; Hangover 11.16 and its FEX package from the official release if missing); extracts
# the installer (and keeps a hard-linked clean copy, game-ss2.pristine); applies GOG's
# winmm_override music files and VideoMode=2 (800x600); installs cnc-ddraw; creates the Wine
# prefix; installs the shortcut. Each step leaves a marker in <home>/.setup/, so a second run
# resumes; delete a marker to redo a step. Uses sudo only for apt. Nothing outside the game home
# is changed except apt packages and the shortcut. The optional 1280x720 widescreen patch is not
# part of the setup (README, "Widescreen").
set -euo pipefail

INSTALLER_DIR=""; GAME_HOME="${SS2_HOME:-$HOME/ss2}"; ALLOW_UPGRADES=0; DESKTOP=1; JOBS=3; CHECK=0
usage() { echo "$1" >&2; echo "usage: setup.sh [--installer DIR] [--home DIR] [--allow-upgrades] [--no-desktop] [--jobs N] [--check]" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --installer) [ $# -ge 2 ] || usage "--installer needs a folder"; INSTALLER_DIR="$2"; shift 2 ;;
    --home) [ $# -ge 2 ] || usage "--home needs a folder"; GAME_HOME="$2"; shift 2 ;;
    --allow-upgrades) ALLOW_UPGRADES=1; shift ;;
    --no-desktop) DESKTOP=0; shift ;;
    --jobs) [ $# -ge 2 ] || usage "--jobs needs a number"; JOBS="$2"; shift 2 ;;
    --check) CHECK=1; shift ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) usage "unknown option: $1" ;;
  esac
done
case "$JOBS" in ''|*[!0-9]*) usage "--jobs needs a number" ;; esac

SRC="$(cd "$(dirname "$0")/../.." && pwd)"
case "$GAME_HOME" in /*) ;; *) GAME_HOME="$PWD/$GAME_HOME" ;; esac
H_="$GAME_HOME"; export SS2_HOME="$H_"
MARK="$H_/.setup"
G="$H_/game-ss2"
if [ "$CHECK" = 0 ]; then
  mkdir -p "$MARK" "$H_/logs" "$H_/downloads" "$H_/prefixes"
  LOG="$H_/logs/setup-$(date +%Y%m%d-%H%M%S).log"
  exec > >(tee -a "$LOG") 2>&1
fi

# Pinned: what the working Pi uses. Hangover checksum from its official release page.
HANGOVER_VER=11.16
HANGOVER_TAR="hangover_${HANGOVER_VER}_debian13_trixie_arm64.tar"
HANGOVER_URL="https://github.com/AndreRH/hangover/releases/download/hangover-${HANGOVER_VER}/${HANGOVER_TAR}"
HANGOVER_SHA=b5493f5903ab3c05f78bf4c03b06ac0005eb26f732437748c1592fefa45e861a
# GOG offline installer tested (2.2, build 13718). Another build may work; the script only warns.
GOG_SHA=b78b6c41678352babb5eb15a855c3ea3e78dcb10309cfc973a8bbe653f5f8109
APT_PKGS=(innoextract unzip curl ca-certificates)
# hangover-wine plus the FEX back-end: under Hangover's default WowBox64 saving hangs forever.
HANGOVER_PKGS=(hangover-wine hangover-libwow64fex)

STEPS=8; STEP=0
step()  { STEP=$((STEP+1)); printf '\n==> [%d/%d] %s\n' "$STEP" "$STEPS" "$*"; }
die()   { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
needs() { printf '\nNEEDS YOU: %s\n' "$*" >&2; exit 3; }
done_() { [ -f "$MARK/$1.done" ]; }
mark()  { touch "$MARK/$1.done"; }
existing_dir() { local d="$1"; while [ ! -d "$d" ]; do d="$(dirname "$d")"; done; echo "$d"; }
missing() { local p; for p in "$@"; do dpkg -s "$p" >/dev/null 2>&1 || echo "$p"; done; }

# apt with a dry run first: stop if anything installed would be upgraded or removed.
apt_sim() {
  local sim
  sim=$(apt-get -s install --no-install-recommends "$@" 2>/dev/null) || die "apt-get -s install $* failed"
  if echo "$sim" | grep -qE '^(Remv|Inst [^ ]+ \[)'; then
    echo "$sim" | grep -E '^(Remv|Inst [^ ]+ \[)'
    [ "$ALLOW_UPGRADES" = 1 ] || needs "apt would upgrade or remove the packages above. Check them, then rerun with --allow-upgrades if that is fine."
  fi
}
apt_install() { apt_sim "$@"; sudo apt-get install -y --no-install-recommends "$@"; }

# Records which installer was used and whether it is the tested build (read by installed.json).
hash_installer() {
  if [ "$(sha256sum "$INSTALLER" | cut -d' ' -f1)" = "$GOG_SHA" ]; then T=yes; else T=no
    echo "NOTE: this installer is not the tested build 2.2 (13718) (SHA-256 differs); continuing."
  fi
  [ "$CHECK" = 1 ] || printf '%s %s\n' "$(basename "$INSTALLER")" "$T" > "$MARK/installer.txt"
  echo "installer: $INSTALLER (tested build: $T)"
}

write_installed() {
  python3 -I - "$H_/game.json" "$MARK/installer.txt" "$MARK/installed.json" "$H_" <<'PY'
import datetime, json, os, sys
g = json.load(open(sys.argv[1]))
name, tested = (open(sys.argv[2]).read().split() + ["", "unknown"])[:2] if os.path.exists(sys.argv[2]) else ("", "unknown")
json.dump({"slug": g["slug"], "short_id": g["short_id"], "wrapper_version": g["wrapper"]["version"],
           "home": sys.argv[4], "installer": name, "installer_tested": tested,
           "installed": datetime.datetime.now().isoformat(timespec="seconds")},
          open(sys.argv[3], "w"), indent=2)
PY
  echo "recorded: $MARK/installed.json"
}

install_shortcuts() {
  [ "$DESKTOP" = 1 ] || { echo "skipped (--no-desktop)"; return 0; }
  local t f targets=("$HOME/.local/share/applications")
  [ -d "$HOME/Desktop" ] && targets+=("$HOME/Desktop")
  for t in "${targets[@]}"; do
    mkdir -p "$t"
    for f in "$H_"/config/desktop/*.desktop; do
      sed "s#@GAME_HOME@#$H_#g" "$f" > "$t/$(basename "$f")"
      chmod +x "$t/$(basename "$f")"
    done
  done
  echo "shortcuts in: ${targets[*]}"
}

# Replace a file instead of writing into it: game-ss2.pristine shares its files as hard links.
replace() { rm -f "$2"; cp "$1" "$2"; }
# sudtest.ini has Windows line ends; keep them.
set_videomode() {
  local t; t="$(mktemp)"
  sed "s/^VideoMode=.*/VideoMode=$1\r/" "$G/sudtest.ini" | sed 's/\r\r/\r/' > "$t"
  replace "$t" "$G/sudtest.ini"; rm -f "$t"
}

step "Checks"
[ "$(uname -m)" = aarch64 ] || needs "needs 64-bit Raspberry Pi OS (aarch64); this is $(uname -m)."
. /etc/os-release
[ "${VERSION_CODENAME:-}" = trixie ] || needs "needs Raspberry Pi OS / Debian 13 'trixie' (Hangover's package is built for it); this is ${PRETTY_NAME:-unknown}."
[ "$(getconf PAGESIZE)" = 4096 ] || needs "the kernel uses $(getconf PAGESIZE)-byte pages; Hangover needs 4 KB pages. On a Pi 5 add 'kernel=kernel8.img' to /boot/firmware/config.txt and reboot."
INSTALLER=""
if ! done_ extract && [ ! -f "$G/game_exe.exe" ]; then
  [ -n "$INSTALLER_DIR" ] || needs "give the folder with your GOG installer: --installer DIR"
  INSTALLER=$(ls "$INSTALLER_DIR"/setup_sudden_strike_2_*.exe 2>/dev/null | head -1)
  [ -n "$INSTALLER" ] || needs "no setup_sudden_strike_2_*.exe in $INSTALLER_DIR"
fi
FREE=$(df -Pk "$(existing_dir "$H_")" | awk 'NR==2{print $4}')
[ "$FREE" -gt 3000000 ] || done_ extract || [ -f "$G/game_exe.exe" ] || needs "needs about 3 GB free in $H_ (game 0.5 GB, Wine prefix about 1.5 GB)"
[ "$CHECK" = 1 ] || sudo true || needs "needs sudo for apt."
echo "game home: $H_"
if [ "$CHECK" = 1 ]; then
  need=($(missing "${APT_PKGS[@]}"))
  if [ ${#need[@]} -gt 0 ]; then echo "apt will install: ${need[*]}"; apt_sim "${need[@]}"; fi
  hneed=($(missing "${HANGOVER_PKGS[@]}"))
  [ ${#hneed[@]} -eq 0 ] || echo "Hangover $HANGOVER_VER will be downloaded; apt will install: ${hneed[*]}"
  [ -z "$INSTALLER" ] || hash_installer
  printf '\nREADY: this Pi can run the setup.\n'; exit 0
fi

step "Scripts and config into $H_"
if [ "$SRC" != "$H_" ]; then
  mkdir -p "$H_/scripts/pi" "$H_/config"
  cp -f "$SRC"/scripts/pi/*.sh "$H_/scripts/pi/"
  cp -rf "$SRC"/config/. "$H_/config/"
  cp -f "$SRC/game.json" "$H_/game.json"
fi
chmod +x "$H_"/scripts/pi/*.sh
echo "done"

step "Packages"
if ! done_ packages; then
  need=($(missing "${APT_PKGS[@]}"))
  if [ ${#need[@]} -gt 0 ]; then apt_install "${need[@]}"; else echo "${APT_PKGS[*]}: installed."; fi
  hneed=($(missing "${HANGOVER_PKGS[@]}"))
  if [ ${#hneed[@]} -eq 0 ]; then
    echo "Hangover: $(dpkg-query -W -f='${Version}' hangover-wine) with FEX (libwow64fex) is installed."
    case "$(dpkg-query -W -f='${Version}' hangover-wine)" in
      "$HANGOVER_VER"*) ;; *) echo "NOTE: tested with Hangover $HANGOVER_VER; this Pi has another version." ;;
    esac
  else
    cd "$H_/downloads"
    if [ ! -f "$HANGOVER_TAR" ]; then
      curl -fL --retry 3 -o "$HANGOVER_TAR.part" "$HANGOVER_URL" && mv -f "$HANGOVER_TAR.part" "$HANGOVER_TAR"
    fi
    echo "$HANGOVER_SHA  $HANGOVER_TAR" | sha256sum -c - || die "Hangover download checksum mismatch; delete $H_/downloads/$HANGOVER_TAR and retry."
    mkdir -p "hangover-$HANGOVER_VER" && tar -xf "$HANGOVER_TAR" -C "hangover-$HANGOVER_VER"
    debs=()
    for p in "${hneed[@]}"; do
      d=$(ls "$H_/downloads/hangover-$HANGOVER_VER/${p}_"*_arm64.deb 2>/dev/null | head -1)
      [ -n "$d" ] || die "no ${p}_*_arm64.deb in the Hangover $HANGOVER_VER release"
      debs+=("$d")
    done
    apt_install "${debs[@]}"
  fi
  mark packages
fi

step "Extracting the game (about a minute)"
if ! done_ extract && [ -f "$G/game_exe.exe" ]; then
  # Set up by hand earlier (no markers): keep the game, its saves and settings as they are.
  echo "game folder already present: kept (saves and settings stay)."
  mark extract; mark gogfiles
fi
if ! done_ extract; then
  hash_installer
  rm -rf "$H_/game-ss2.x" "$G" "$G.pristine"
  innoextract --gog -s --progress=0 -d "$H_/game-ss2.x" "$INSTALLER"
  mv "$H_/game-ss2.x/app" "$G"
  rm -rf "$H_/game-ss2.x"
  [ -f "$G/game_exe.exe" ] || die "game_exe.exe missing after extraction"
  # A clean copy for later (hard links: no extra space). See docs/game-files-pi4.md.
  cp -al "$G" "$G.pristine"
  mark extract
fi
echo "game in $G"

step "GOG music files (winmm_override) and VideoMode=2 (800x600)"
if ! done_ gogfiles; then
  # GOG's installer copies __support/winmm_override over the game: an n2Game_Dll.dll that plays
  # the Ogg music through the included win32.dll instead of CD audio.
  [ -d "$G/__support/winmm_override" ] || die "$G/__support/winmm_override is missing"
  (cd "$G/__support/winmm_override" && find . -type f) | while read -r f; do
    mkdir -p "$G/$(dirname "$f")"; replace "$G/__support/winmm_override/$f" "$G/$f"
  done
  set_videomode 2
  mark gogfiles
fi
grep -a '^VideoMode' "$G/sudtest.ini"

step "cnc-ddraw 7.1.0.0 (stretched full screen)"
if ! done_ cncddraw && grep -q cnc-ddraw "$G/ddraw.ini" 2>/dev/null; then
  echo "cnc-ddraw already in the game folder: kept (its ddraw.ini stays)."; mark cncddraw
fi
if ! done_ cncddraw; then
  GAME_DIRS=game-ss2 "$H_/scripts/pi/install-cnc-ddraw.sh"
  mark cncddraw
else echo "already done"; fi

step "Wine prefix"
set -a; . "$H_/config/pi4-ss2.env"; . "$H_/config/track-hangover.env"; set +a
export DISPLAY="${DISPLAY:-${DISPLAY_NUM:-:0}}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export WINEPREFIX WINEARCH HODLL WINEDEBUG=-all WINEDLLOVERRIDES="mscoree=;mshtml="
if ! done_ prefix && [ -f "$WINEPREFIX/system.reg" ]; then
  echo "Wine prefix already present: kept ($WINEPREFIX)."; mark prefix
fi
if ! done_ prefix; then
  $WINE_CMD wineboot -i || true
  $WINESERVER_CMD -w
  [ -f "$WINEPREFIX/system.reg" ] || die "the Wine prefix was not created ($WINEPREFIX)."
  mark prefix
else echo "already done"; fi

step "Shortcut"
install_shortcuts
write_installed

printf '\n==> Done\n'
echo "Start the game with the 'Sudden Strike 2' shortcut or: $H_/scripts/pi/play.sh"
