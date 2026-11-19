#!/usr/bin/env bash
# setup-new-pi.sh: set up Medieval: Total War on a fresh Raspberry Pi, the same way as the
# working Pi 4 (Track A: Hangover 11.16 / WowBox64, the d3d9lazy shim, a private patched Mesa,
# full screen through play.sh). Guide: docs/NEW-PI-SETUP.md.
#
# Run it ON THE PI, from a clone of this project, inside tmux, because the
# Mesa build alone takes about 20 minutes on a Pi 4:
#
#   tmux new -s setup
#   ~/pi-total-war/scripts/pi/setup-new-pi.sh --installer ~/gog
#
#   --installer DIR   folder holding your GOG offline backup installer: setup_medieval_total_war_*.exe
#                     AND its .bin file (both from your GOG library), e.g. ~/gog.
#   --allow-upgrades  continue even if apt wants to upgrade or remove installed packages
#                     (default: stop, so a Pi that also runs a server is not changed by surprise)
#   --jobs N          parallel jobs for the Mesa build (default 3; a 4 GB Pi 4 is fine with 3)
#   --private-wine    unpack Hangover into ~/mtw/hangover instead of installing it as the system
#                     Wine. Use this if the Pi already has a Wine package for other programs: the
#                     Hangover package would replace it. Only Hangover's libraries come from apt.
#
# Every step leaves a marker in ~/mtw/.setup/, so running the script again skips finished steps
# and resumes after a failure. Delete a marker to redo that step. Nothing outside ~/mtw is
# changed except apt packages and the two desktop shortcuts (~/Desktop and the app menu).
# It uses sudo only for apt.
set -euo pipefail

INSTALLER_DIR=""
ALLOW_UPGRADES=0
PRIVATE_WINE=0
JOBS=3
while [ $# -gt 0 ]; do
  case "$1" in
    --installer) INSTALLER_DIR="$2"; shift 2 ;;
    --allow-upgrades) ALLOW_UPGRADES=1; shift ;;
    --jobs) JOBS="$2"; shift 2 ;;
    --private-wine) PRIVATE_WINE=1; shift ;;
    -h|--help) sed -n '2,27p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
MTW="$HOME/mtw"
MARK="$MTW/.setup"
mkdir -p "$MTW/logs" "$MARK" "$MTW/downloads" "$MTW/build" "$MTW/prefixes"
LOG="$MTW/logs/setup-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

# Pinned versions. These are what the working Pi uses; the checksums are from the official
# release pages (Hangover: github.com/AndreRH/hangover, Mesa: archive.mesa3d.org).
HANGOVER_VER=11.16
HANGOVER_TAR="hangover_${HANGOVER_VER}_debian13_trixie_arm64.tar"
HANGOVER_URL="https://github.com/AndreRH/hangover/releases/download/hangover-${HANGOVER_VER}/${HANGOVER_TAR}"
HANGOVER_SHA=b5493f5903ab3c05f78bf4c03b06ac0005eb26f732437748c1592fefa45e861a
MESA_VER=26.2.6
MESA_URL="https://archive.mesa3d.org/mesa-${MESA_VER}.tar.xz"
MESA_SHA=b9436b3e1a8be76fbd4823dc884f90596ab7c6ac5e1867a305e66ffccfb31a92
# GOG offline installer v1 (86311). Another GOG build may also work; the script only warns.
GOG_EXE_SHA=002c6e3c18367a703429e9cd535736c5e4794f0fe58a41510682942897a7fa5c
GOG_BIN_SHA=cf0feed7f7bff4002957ccd38e02748e06286ad86c6ba0c31e381889cebcb1c7

say()  { printf '\n=== %s\n' "$*"; }
die()  { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
done_() { [ -f "$MARK/$1.done" ]; }
mark() { touch "$MARK/$1.done"; }

# apt install with a simulation first: stop if it would upgrade or remove anything.
apt_install() {
  local sim
  sim="$(apt-get -s install --no-install-recommends "$@")" || die "apt simulation failed for: $*"
  if printf '%s\n' "$sim" | grep -Eq '^(Remv |Inst [^ ]+ \[)'; then
    printf '%s\n' "$sim" | grep -E '^(Remv |Inst [^ ]+ \[)'
    if [ "$ALLOW_UPGRADES" != 1 ]; then
      die "apt would upgrade or remove the packages above. Nothing was installed. Check them, then rerun with --allow-upgrades if that is fine on this Pi."
    fi
  fi
  echo "new packages: $(printf '%s\n' "$sim" | grep -c '^Inst ' || true)"
  sudo apt-get install -y --no-install-recommends "$@"
}

# ---------------------------------------------------------------------------------------------
say "1/9 Checking this Pi"
[ "$(uname -m)" = aarch64 ] || die "needs a 64-bit (aarch64) OS; this is $(uname -m)."
. /etc/os-release
[ "${VERSION_CODENAME:-}" = trixie ] || die "needs Debian 13 'trixie' / Raspberry Pi OS based on it (Hangover's package is built for trixie); this is ${PRETTY_NAME:-unknown}."
PAGE="$(getconf PAGESIZE)"
if [ "$PAGE" != 4096 ]; then
  die "the kernel uses ${PAGE}-byte pages; Hangover needs 4 KB pages. On a Pi 5 add the line
  kernel=kernel8.img
to /boot/firmware/config.txt and reboot, then run this script again."
fi
FREE_GB=$(( $(df -Pk "$HOME" | awk 'NR==2{print $4}') / 1024 / 1024 ))
[ "$FREE_GB" -ge 10 ] || die "needs about 10 GB free in $HOME; only ${FREE_GB} GB free."
sudo true || die "needs sudo for apt."
grep -q "Raspberry Pi 4" /proc/device-tree/model 2>/dev/null ||
  echo "NOTE: this is not a Pi 4 ($(tr -d '\0' </proc/device-tree/model 2>/dev/null)). The setup was only ever tested on a Pi 4."
echo "OK: $(tr -d '\0' </proc/device-tree/model 2>/dev/null), ${PRETTY_NAME}, ${FREE_GB} GB free"

# Another Wine on this Pi? The hangover-wine package declares a conflict with Debian's wine
# packages and takes over /usr/bin/wine, so installing it would remove or overwrite that Wine.
if [ -f "$MARK/hangover.done" ] && [ -x "$MTW/hangover/usr/bin/wine" ]; then PRIVATE_WINE=1; fi
other_wine="$(dpkg-query -W -f='${Package} ${Status}\n' 'wine' 'wine32' 'wine64' 'libwine' \
  'wine-stable' 'wine-devel' 'wine-staging' 'winehq-*' 2>/dev/null | awk '/ installed$/{print $1}' | tr '\n' ' ' || true)"
if [ -e /usr/bin/wine ] && ! dpkg -S /usr/bin/wine 2>/dev/null | grep -q '^hangover-wine:'; then
  other_wine="$other_wine/usr/bin/wine (not from Hangover)"
fi
if [ -n "${other_wine// /}" ] && [ "$PRIVATE_WINE" != 1 ]; then
  die "this Pi already has a Wine: $other_wine
Installing Hangover as the system Wine would replace it. Either rerun with --private-wine
(Hangover goes into $MTW/hangover and your Wine stays as it is), or remove that Wine yourself
first if you want Hangover to become the system Wine."
fi
path_wine="$(command -v wine || true)"
if [ -n "$path_wine" ] && [ "$path_wine" != /usr/bin/wine ]; then
  echo "NOTE: 'wine' on your PATH is $path_wine. It stays your default 'wine'; the game always calls Hangover by its full path and uses its own prefix in $MTW/prefixes."
fi
[ "$PRIVATE_WINE" = 1 ] && echo "Hangover will be unpacked privately into $MTW/hangover (--private-wine)."

if [ -z "$INSTALLER_DIR" ] && ! done_ game; then
  die "give the folder with the GOG installer: --installer DIR"
fi

# ---------------------------------------------------------------------------------------------
say "2/9 Copying the project's scripts and config to $MTW"
if [ "$REPO" != "$MTW" ]; then
  for d in scripts config tools patches; do
    [ -d "$REPO/$d" ] || die "$REPO/$d is missing; run the script from a full copy of the project."
    mkdir -p "$MTW/$d"
    cp -r "$REPO/$d/." "$MTW/$d/"
  done
  chmod +x "$MTW"/scripts/pi/*.sh
fi
echo "OK"

# ---------------------------------------------------------------------------------------------
say "3/9 Installing helper and build packages (apt, simulated first)"
if ! done_ apt; then
  sudo apt-get update
  apt_install innoextract xdotool grim tmux curl ca-certificates xz-utils patch \
    gcc-mingw-w64-i686 \
    meson ninja-build pkg-config python3-mako python3-yaml python3-packaging python3-ply \
    bison flex g++ libdrm-dev libexpat1-dev zlib1g-dev libzstd-dev libx11-dev libxext-dev \
    libxfixes-dev libxcb-glx0-dev libxcb-shm0-dev libx11-xcb-dev libxcb-dri2-0-dev \
    libxcb-dri3-dev libxcb-present-dev libxcb-sync-dev libxcb-xfixes0-dev libxshmfence-dev \
    libxxf86vm-dev libxrandr-dev libxcb-randr0-dev libwayland-dev wayland-protocols \
    libwayland-egl-backend-dev libglvnd-dev libglvnd-core-dev
  mark apt
else echo "already done"; fi

# ---------------------------------------------------------------------------------------------
say "4/9 Installing Hangover $HANGOVER_VER (official release)"
if ! done_ hangover; then
  cd "$MTW/downloads"
  [ -f "$HANGOVER_TAR" ] || curl -fL --retry 3 -o "$HANGOVER_TAR" "$HANGOVER_URL"
  echo "$HANGOVER_SHA  $HANGOVER_TAR" | sha256sum -c - || die "Hangover download checksum mismatch; delete $MTW/downloads/$HANGOVER_TAR and retry."
  mkdir -p "hangover-$HANGOVER_VER" && tar -xf "$HANGOVER_TAR" -C "hangover-$HANGOVER_VER"
  H="$MTW/downloads/hangover-$HANGOVER_VER"
  DEBS=("$H/hangover-wine_${HANGOVER_VER}~trixie_arm64.deb"
        "$H/hangover-libarm64ecfex_${HANGOVER_VER}_arm64.deb"
        "$H/hangover-wowbox64_${HANGOVER_VER}_arm64.deb")
  if [ "$PRIVATE_WINE" = 1 ]; then
    # Only the libraries Hangover's Wine links against come from apt (first choice of each
    # alternative, version limits dropped); Wine itself is unpacked under ~/mtw.
    # Libraries already present are left alone (so their apt state is not changed).
    libs=()
    for p in $(dpkg-deb -f "${DEBS[0]}" Depends | tr ',' '\n' |
               sed 's/|.*//; s/(.*)//; s/ //g' | grep -v -e '^hangover-' -e '^$'); do
      dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q ' installed$' || libs+=("$p")
    done
    if [ ${#libs[@]} -gt 0 ]; then apt_install "${libs[@]}"; else echo "Hangover's libraries are already installed."; fi
    rm -rf "$MTW/hangover.partial"
    for d in "${DEBS[@]}"; do dpkg-deb -x "$d" "$MTW/hangover.partial"; done
    rm -rf "$MTW/hangover" && mv "$MTW/hangover.partial" "$MTW/hangover"
    "$MTW/hangover/usr/bin/wine" --version
  else
    apt_install "${DEBS[@]}"
    /usr/bin/wine --version
  fi
  mark hangover
else echo "already done"; fi

# ---------------------------------------------------------------------------------------------
say "5/9 Unpacking the game into $MTW/game-lazy (innoextract, no emulation)"
if ! done_ game; then
  shopt -s nullglob
  exes=("$INSTALLER_DIR"/setup_medieval_total_war*.exe)
  bins=("$INSTALLER_DIR"/setup_medieval_total_war*.bin)
  shopt -u nullglob
  [ ${#exes[@]} -eq 1 ] || die "expected one setup_medieval_total_war*.exe in $INSTALLER_DIR, found ${#exes[@]}."
  [ ${#bins[@]} -ge 1 ] || die "the installer's .bin file is missing from $INSTALLER_DIR (it must sit beside the .exe)."
  echo "Checking installer checksums (takes a minute)..."
  if [ "$(sha256sum "${exes[0]}" | cut -d' ' -f1)" != "$GOG_EXE_SHA" ] ||
     [ "$(sha256sum "${bins[0]}" | cut -d' ' -f1)" != "$GOG_BIN_SHA" ]; then
    echo "WARNING: this is not the GOG build v1 (86311) the project was tested with. Continuing anyway."
  fi
  rm -rf "$MTW/game-lazy.partial"
  innoextract --gog -d "$MTW/game-lazy.partial" "${exes[0]}"
  [ -f "$MTW/game-lazy.partial/Medieval_TW.exe" ] || die "Medieval_TW.exe not found after unpacking."
  rm -rf "$MTW/game-lazy" && mv "$MTW/game-lazy.partial" "$MTW/game-lazy"
  mark game
else echo "already done"; fi

# ---------------------------------------------------------------------------------------------
say "6/9 Building the d3d9lazy shim (the project's own D3D9 speed-up DLL)"
if ! done_ shim; then
  mkdir -p "$MTW/tools/d3d9lazy"
  cd "$MTW/tools/d3d9lazy"
  i686-w64-mingw32-gcc -O2 -msse2 -Wall -shared -o d3d9.dll d3d9lazy.c -Wl,--kill-at -static-libgcc
  cp d3d9.dll "$MTW/game-lazy/d3d9.dll"
  sha256sum "$MTW/game-lazy/d3d9.dll"
  mark shim
else echo "already done"; fi

# ---------------------------------------------------------------------------------------------
say "7/9 Building the patched Mesa into $MTW/mesa-patched (about 20 minutes on a Pi 4)"
if ! done_ mesa; then
  cd "$MTW/downloads"
  [ -f "mesa-$MESA_VER.tar.xz" ] || curl -fL --retry 3 -o "mesa-$MESA_VER.tar.xz" "$MESA_URL"
  echo "$MESA_SHA  mesa-$MESA_VER.tar.xz" | sha256sum -c - || die "Mesa download checksum mismatch; delete $MTW/downloads/mesa-$MESA_VER.tar.xz and retry."
  rm -rf "$MTW/build/mesa-$MESA_VER"
  tar -xf "mesa-$MESA_VER.tar.xz" -C "$MTW/build"
  cd "$MTW/build/mesa-$MESA_VER/src/gallium/drivers/v3d"
  patch -p1 --dry-run < "$MTW/patches/mesa-v3d-busy-range.patch" >/dev/null || die "the Mesa patch does not apply."
  patch -p1 < "$MTW/patches/mesa-v3d-busy-range.patch"
  cd "$MTW/build/mesa-$MESA_VER"
  meson setup _build -Dprefix="$MTW/mesa-patched" -Dbuildtype=release \
    -Dgallium-drivers=v3d,vc4 -Dvulkan-drivers= -Dplatforms=x11,wayland -Dglx=dri \
    -Degl=enabled -Dgbm=enabled -Dgles1=disabled -Dgles2=enabled -Dglvnd=enabled \
    -Dllvm=disabled -Dvideo-codecs= -Dgallium-va=disabled -Dlmsensors=disabled \
    -Dvalgrind=disabled -Dlibunwind=disabled
  ninja -C _build -j "$JOBS"
  ninja -C _build install
  [ -f "$MTW/mesa-patched/share/glvnd/egl_vendor.d/50_mesa.json" ] || die "patched Mesa did not install where the profiles expect it."
  mark mesa
else echo "already done"; fi

# ---------------------------------------------------------------------------------------------
say "8/9 Creating the Wine prefix (a few minutes; Mono/RPC messages are normal)"
set -a
. "$MTW/config/pi4-lazy.env"
. "$MTW/config/track-hangover.env"
set +a
export DISPLAY="${DISPLAY:-:0}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export WINEPREFIX WINEDEBUG=fixme-all
if ! done_ prefix; then
  echo "using $WINE_CMD"
  WINEDLLOVERRIDES="mscoree=;mshtml=" $WINE_CMD wineboot -u || true
  $WINESERVER_CMD -w
  [ -f "$WINEPREFIX/system.reg" ] || die "the Wine prefix was not created ($WINEPREFIX)."
  mark prefix
else echo "already done"; fi

# ---------------------------------------------------------------------------------------------
say "9/9 Adding the desktop shortcuts"
mkdir -p "$HOME/.local/share/applications"
targets=("$HOME/.local/share/applications")
[ -d "$HOME/Desktop" ] && targets+=("$HOME/Desktop")
for t in "${targets[@]}"; do
  for f in "$MTW"/config/desktop/*.desktop; do
    sed "s#/home/admin/mtw#$MTW#g" "$f" > "$t/$(basename "$f")"
    chmod +x "$t/$(basename "$f")"
  done
done
echo "shortcuts in: ${targets[*]}"

say "Done"
cat <<EOF
Start the game with the "Medieval Total War" shortcut, or:
  $MTW/scripts/pi/play.sh            full screen (default)
  $MTW/scripts/pi/play.sh --fps      with a frame-rate counter
  $MTW/scripts/pi/play.sh --window   in a 1024x768 Wine desktop window
The first start takes longer. Pick the battle resolution in the game under Options > Video
(800x600 was the tested one). This log: $LOG
EOF
