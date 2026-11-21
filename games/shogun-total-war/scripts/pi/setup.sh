#!/usr/bin/env bash
# setup.sh: set up Shogun: Total War on a Raspberry Pi the same way as the working Pi 4
# (Track B: Box64 + x86-64 Wine 9.17 in WoW64 mode, this project's own winex11.so and dsound.dll,
# the d3d9lazy shim, a private patched Mesa, full screen through play.sh). Guide:
# docs/NEW-PI-SETUP.md. Standalone: nothing is taken from other game projects on the Pi; every
# component is downloaded from its official source (pinned version, SHA-256 checked) and built
# here.
#
# Run it ON THE PI from a copy of this folder, inside tmux (the builds take about an hour on a
# Pi 4):
#
#   tmux new -s stw
#   <this folder>/scripts/pi/setup.sh --installer ~/gog
#
#   --installer DIR   folder holding the GOG offline installer
#                     setup_shogun_total_wartm_gog_v1_(86790).exe (from your GOG library)
#   --home DIR        where the game is set up (default ~/stw)
#   --allow-upgrades  continue even if apt wants to upgrade or remove installed packages
#                     (default: stop, so a Pi that also runs a server is not changed by surprise)
#   --no-desktop      do not install the shortcuts (desktop and app menu)
#   --jobs N          parallel build jobs (default 3; fine for a 4 GB Pi 4)
#   --check           only check this Pi and the installer, change nothing
#
# Standard wrapper interface (general-pi-wrappers README, "Setup interface"). Exit codes:
# 0 done, 1 failed (run again to resume), 2 usage error, 3 needs you (fix what it says, rerun).
# Every step leaves a marker in <home>/.setup/, so running the script again skips finished steps
# and resumes after a failure; delete a marker to redo that step. An existing game folder
# (game-lazy) and Wine prefix are kept (saves stay); their DLLs are refreshed. Nothing outside the
# game home is changed except apt packages and the shortcuts. sudo is used only for apt.
set -euo pipefail

INSTALLER_DIR=""; GAME_HOME="${STW_HOME:-$HOME/stw}"; ALLOW_UPGRADES=0; DESKTOP=1; JOBS=3; CHECK=0
usage() { echo "$1" >&2; echo "usage: setup.sh [--installer DIR] [--home DIR] [--allow-upgrades] [--no-desktop] [--jobs N] [--check]" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --installer) [ $# -ge 2 ] || usage "--installer needs a folder"; INSTALLER_DIR="$2"; shift 2 ;;
    --home) [ $# -ge 2 ] || usage "--home needs a folder"; GAME_HOME="$2"; shift 2 ;;
    --allow-upgrades) ALLOW_UPGRADES=1; shift ;;
    --no-desktop) DESKTOP=0; shift ;;
    --jobs) [ $# -ge 2 ] || usage "--jobs needs a number"; JOBS="$2"; shift 2 ;;
    --check) CHECK=1; shift ;;
    -h|--help) sed -n '2,29p' "$0"; exit 0 ;;
    *) usage "unknown option: $1" ;;
  esac
done
case "$JOBS" in ''|*[!0-9]*) usage "--jobs needs a number" ;; esac

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
case "$GAME_HOME" in /*) ;; *) GAME_HOME="$PWD/$GAME_HOME" ;; esac
STW="$GAME_HOME"
export STW_HOME="$STW"
MARK="$STW/.setup"
DL="$STW/downloads"
if [ "$CHECK" = 0 ]; then
  mkdir -p "$STW/logs" "$MARK" "$DL" "$STW/build" "$STW/src" "$STW/prefixes" "$STW/cache"
  LOG="$STW/logs/setup-$(date +%Y%m%d-%H%M%S).log"
  exec > >(tee -a "$LOG") 2>&1
fi

# Pinned versions (what the working Pi 4 runs). Checksums from the official downloads.
BOX64_REPO=https://github.com/ptitSeb/box64
BOX64_COMMIT=a46caf3b0bf885b563473ee8818df2e05e4c47e7          # 0.4.5 development, 2026-11-14
WINE_BIN_URL=https://github.com/Kron4ek/Wine-Builds/releases/download/9.17/wine-9.17-amd64-wow64.tar.xz
WINE_BIN_SHA=684c8fe59fc27e339115e57c4a50484d895f8557e9b084d520fde0a33253fdf9
WINE_SRC_URL=https://dl.winehq.org/wine/source/9.x/wine-9.17.tar.xz
WINE_SRC_SHA=3edb7eb6f31bb5c3f7378dd5623da9d95f7d4d6d7c8378afd89c8e3a30aa080c
MESA_VER=26.2.6
MESA_URL="https://archive.mesa3d.org/mesa-${MESA_VER}.tar.xz"
MESA_SHA=b9436b3e1a8be76fbd4823dc884f90596ab7c6ac5e1867a305e66ffccfb31a92
GOG_EXE_NAME='setup_shogun_total_wartm_gog_v1_(86790).exe'
GOG_EXE_SHA=bed36e39c45bc447f21a25c7de5f3f09a09587ac176129cd3621fe9c5f216b28
APT_PKGS=(innoextract xdotool grim imagemagick zenity tmux curl ca-certificates xz-utils patch
  git cmake python3 gcc g++ make flex bison gcc-mingw-w64-i686
  gcc-x86-64-linux-gnu libc6-dev-amd64-cross
  libx11-dev libxext-dev libxrender-dev libxrandr-dev libxfixes-dev libxxf86vm-dev libxi-dev
  libxinerama-dev libxcursor-dev libxcomposite-dev libgl-dev
  meson ninja-build pkg-config python3-mako python3-yaml python3-packaging python3-ply
  libdrm-dev libexpat1-dev zlib1g-dev libzstd-dev libxcb-glx0-dev libxcb-shm0-dev
  libx11-xcb-dev libxcb-dri2-0-dev libxcb-dri3-dev libxcb-present-dev libxcb-sync-dev
  libxcb-xfixes0-dev libxshmfence-dev libxcb-randr0-dev libwayland-dev wayland-protocols
  libwayland-egl-backend-dev libglvnd-dev libglvnd-core-dev)

STEPS=11; STEP=0
step()  { STEP=$((STEP+1)); printf '\n==> [%d/%d] %s\n' "$STEP" "$STEPS" "$*"; }
die()   { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
needs() { printf '\nNEEDS YOU: %s\n' "$*" >&2; exit 3; }
done_() { [ -f "$MARK/$1.done" ]; }
mark()  { touch "$MARK/$1.done"; }
existing_dir() { local d="$1"; while [ ! -d "$d" ]; do d="$(dirname "$d")"; done; echo "$d"; }
fetch() { # fetch <url> <sha256> -> $DL/<basename>
  local f="$DL/$(basename "$1")"
  if [ ! -f "$f" ]; then
    curl -fL --retry 3 -o "$f.part" "$1" || die "download failed: $1"
    mv "$f.part" "$f"
  fi
  echo "$2  $f" | sha256sum -c - || die "checksum mismatch for $f; delete it and rerun."
}

# apt install with a simulation first: stop if it would upgrade or remove anything.
SIM=""
apt_sim() {
  SIM="$(apt-get -s install --no-install-recommends "$@" 2>/dev/null)" || die "apt simulation failed for: $*"
  if printf '%s\n' "$SIM" | grep -Eq '^(Remv |Inst [^ ]+ \[)'; then
    printf '%s\n' "$SIM" | grep -E '^(Remv |Inst [^ ]+ \[)'
    if [ "$ALLOW_UPGRADES" != 1 ]; then
      needs "apt would upgrade or remove the packages above. Nothing was installed. Check them, then rerun with --allow-upgrades if that is fine on this Pi."
    fi
  fi
  echo "new packages: $(printf '%s\n' "$SIM" | grep -c '^Inst ' || true)"
}
apt_install() {
  apt_sim "$@"
  if printf '%s\n' "$SIM" | grep -q '^Inst '; then
    sudo apt-get install -y --no-install-recommends "$@"
  fi
}

# Records which installer was used and whether it is the tested build (read by installed.json).
hash_installer() {
  echo "Checking the installer checksum (takes a minute)..."
  if [ "$(sha256sum "$EXE" | cut -d' ' -f1)" = "$GOG_EXE_SHA" ]; then T=yes; else T=no
    echo "WARNING: this is not the GOG build v1 (86790) the project was tested with. Continuing anyway."
  fi
  [ "$CHECK" = 1 ] || printf '%s %s\n' "$GOG_EXE_NAME" "$T" > "$MARK/installer.txt"
  echo "installer: $EXE (tested build: $T)"
}

write_installed() {
  python3 -I - "$STW/game.json" "$MARK/installer.txt" "$MARK/installed.json" "$STW" <<'PY'
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
    for f in "$STW"/config/desktop/*.desktop; do
      sed "s#@GAME_HOME@#$STW#g" "$f" > "$t/$(basename "$f")"
      chmod +x "$t/$(basename "$f")"
    done
  done
  echo "shortcuts in: ${targets[*]}"
}

# ---------------------------------------------------------------------------------------------
step "Checking this Pi"
[ "$(uname -m)" = aarch64 ] || needs "needs a 64-bit (aarch64) OS; this is $(uname -m)."
. /etc/os-release
[ "${VERSION_CODENAME:-}" = trixie ] || echo "NOTE: tested on Debian 13 'trixie' only; this is ${PRETTY_NAME:-unknown}."
PAGE="$(getconf PAGESIZE)"
if [ "$PAGE" != 4096 ]; then
  needs "the kernel uses ${PAGE}-byte pages; Wine needs 4 KB pages. On a Pi 5 add the line
  kernel=kernel8.img
to /boot/firmware/config.txt and reboot, then run this script again."
fi
FREE_GB=$(( $(df -Pk "$(existing_dir "$STW")" | awk 'NR==2{print $4}') / 1024 / 1024 ))
[ "$FREE_GB" -ge 12 ] || done_ mesa || needs "needs about 12 GB free for $STW; only ${FREE_GB} GB free."
[ "$CHECK" = 1 ] || sudo true || needs "needs sudo for apt."
grep -q "Raspberry Pi 4" /proc/device-tree/model 2>/dev/null ||
  echo "NOTE: this is not a Pi 4 ($(tr -d '\0' </proc/device-tree/model 2>/dev/null)). The setup was only tested on a Pi 4."
EXE=""
if [ ! -f "$STW/game-lazy/ShogunM.exe" ]; then
  [ -n "$INSTALLER_DIR" ] || needs "give the folder with the GOG installer: --installer DIR"
  EXE="$INSTALLER_DIR/$GOG_EXE_NAME"
  [ -f "$EXE" ] || needs "not found: $EXE"
fi
echo "OK: $(tr -d '\0' </proc/device-tree/model 2>/dev/null), ${PRETTY_NAME:-?}, ${FREE_GB} GB free, into $STW"
if [ "$CHECK" = 1 ]; then
  done_ apt || apt_sim "${APT_PKGS[@]}"
  [ -z "$EXE" ] || hash_installer
  printf '\nREADY: this Pi can run the setup.\n'; exit 0
fi

# ---------------------------------------------------------------------------------------------
step "Copying the project's scripts, config, tools and patches to $STW"
if [ "$REPO" != "$STW" ]; then
  for d in scripts config tools patches refs; do
    # refs/ (test reference screenshots) is only in the workshop record, not in the wrapper
    [ "$d" = refs ] && [ ! -d "$REPO/$d" ] && continue
    [ -d "$REPO/$d" ] || die "$REPO/$d is missing; run the script from a full copy of the project."
    mkdir -p "$STW/$d"
    cp -r "$REPO/$d/." "$STW/$d/"
  done
  cp -f "$REPO/game.json" "$STW/game.json"
fi
sed -i 's/\r$//' "$STW"/scripts/pi/*.sh "$STW"/config/*.env "$STW"/tools/*/*.py "$STW"/tools/*/*.sh 2>/dev/null || true
chmod +x "$STW"/scripts/pi/*.sh "$STW"/tools/*/*.sh
echo "OK"

# ---------------------------------------------------------------------------------------------
step "Installing helper and build packages (apt, simulated first)"
if ! done_ apt; then
  sudo apt-get update
  apt_install "${APT_PKGS[@]}"
  mark apt
else echo "already done"; fi

# ---------------------------------------------------------------------------------------------
step "Building Box64 (commit ${BOX64_COMMIT:0:7}) into $STW/box64 (about 20 minutes)"
if ! done_ box64; then
  B="$STW/build/box64"
  [ -d "$B/.git" ] || git clone "$BOX64_REPO" "$B"
  git -C "$B" fetch -q origin || true
  git -C "$B" checkout -q "$BOX64_COMMIT"
  cmake -S "$B" -B "$B/_build" -DRPI4ARM64=1 -DCMAKE_BUILD_TYPE=RelWithDebInfo
  cmake --build "$B/_build" -j "$JOBS" --target box64
  # Copied by hand: Box64's "make install" writes /etc/binfmt.d, which this project must not do.
  rm -rf "$STW/box64.partial"
  mkdir -p "$STW/box64.partial/usr/local/bin" "$STW/box64.partial/usr/lib/box64-x86_64-linux-gnu" "$STW/box64.partial/usr/doc/box64"
  cp "$B/_build/box64" "$STW/box64.partial/usr/local/bin/box64"
  cp -a "$B/x64lib/." "$STW/box64.partial/usr/lib/box64-x86_64-linux-gnu/"
  cp "$B/LICENSE" "$STW/box64.partial/usr/doc/box64/"
  rm -rf "$STW/box64" && mv "$STW/box64.partial" "$STW/box64"
  "$STW/box64/usr/local/bin/box64" --version
  mark box64
else echo "already done"; fi

# ---------------------------------------------------------------------------------------------
step "Unpacking Wine 9.17 (Kron4ek's x86-64 WoW64 build) into $STW/wine-x64-9.17"
if ! done_ wine; then
  fetch "$WINE_BIN_URL" "$WINE_BIN_SHA"
  rm -rf "$STW/wine.partial" && mkdir -p "$STW/wine.partial"
  tar -xJf "$DL/$(basename "$WINE_BIN_URL")" -C "$STW/wine.partial" --strip-components=1
  [ -f "$STW/wine.partial/bin/wine" ] || die "Wine archive layout not as expected."
  rm -rf "$STW/wine-x64-9.17" && mv "$STW/wine.partial" "$STW/wine-x64-9.17"
  cp -p "$STW/wine-x64-9.17/lib/wine/x86_64-unix/winex11.so" "$STW/wine-x64-9.17/lib/wine/x86_64-unix/winex11.so.kron4ek"
  rm -f "$MARK/winex11.done"   # the own winex11.so must go into the fresh copy again
  mark wine
else echo "already done"; fi

# ---------------------------------------------------------------------------------------------
step "Building this project's dsound.dll from the Wine 9.17 source (tools/dsound)"
W="$STW/src/wine-9.17"
if ! done_ dsound; then
  fetch "$WINE_SRC_URL" "$WINE_SRC_SHA"
  rm -rf "$W" && tar -xJf "$DL/wine-9.17.tar.xz" -C "$STW/src"
  (cd "$W/dlls/dsound" && python3 -I "$STW/tools/dsound/apply-linear.py")
  (cd "$W/dlls/winex11.drv" && python3 -I "$STW/tools/winex11/apply-gl-nolock.py" \
                            && python3 -I "$STW/tools/winex11/apply-xwayland-modeset.py")
  mkdir -p "$W/build" && cd "$W/build"
  ../configure --enable-archs=i386 --disable-tests --without-x --without-freetype --without-gstreamer \
    --without-vulkan --without-opengl --without-cups --without-dbus --without-gphoto --without-sane \
    --without-krb5 --without-netapi --without-pcap --without-pcsclite --without-sdl --without-usb \
    --without-v4l2 --without-wayland --without-gnutls --without-alsa --without-pulse --without-oss \
    --without-capi --without-unwind --without-udev --without-inotify --without-ffmpeg \
    --without-coreaudio --without-osmesa --without-xinerama
  make -j "$JOBS" __tooldeps__
  make -j "$JOBS" dlls/dsound/i386-windows/dsound.dll
  python3 -I - "$W/build/dlls/dsound/i386-windows/dsound.dll" "$STW/tools/dsound/dsound-native.dll" <<'PY'
import sys
d = bytearray(open(sys.argv[1], 'rb').read())
assert d[64:80] == b'Wine builtin DLL', 'no builtin marker'
d[64:96] = bytes(32)   # Wine would otherwise load its own system copy instead
open(sys.argv[2], 'wb').write(d)
PY
  sha256sum "$STW/tools/dsound/dsound-native.dll"
  rm -f "$MARK/winex11.done"   # winex11 uses this tree's build tools
  mark dsound
else echo "already done"; fi

# ---------------------------------------------------------------------------------------------
step "Building this project's winex11.so (x86-64 cross build, tools/winex11)"
if ! done_ winex11; then
  bash "$STW/tools/winex11/mkcross.sh"
  X="$STW/src/x11cross"
  rm -rf "$W/build64" && mkdir -p "$W/build64" && cd "$W/build64"
  ../configure --host=x86_64-linux-gnu --with-wine-tools=../build --without-mingw --disable-tests \
    --with-x --x-includes="$X/include" --x-libraries="$X/lib" --with-opengl --with-vulkan \
    --without-freetype --without-gstreamer --without-cups --without-dbus --without-gphoto --without-sane \
    --without-krb5 --without-netapi --without-pcap --without-pcsclite --without-sdl --without-usb \
    --without-v4l2 --without-wayland --without-gnutls --without-alsa --without-pulse --without-oss \
    --without-capi --without-unwind --without-udev --without-inotify --without-ffmpeg \
    --without-coreaudio --without-osmesa --without-fontconfig --without-gssapi \
    CFLAGS="-O2 -g" LDFLAGS="-L$X/lib"
  make -j "$JOBS" dlls/winex11.drv/winex11.so
  U="$STW/wine-x64-9.17/lib/wine/x86_64-unix"
  [ -f "$U/winex11.so.kron4ek" ] || cp -p "$U/winex11.so" "$U/winex11.so.kron4ek"
  cp dlls/winex11.drv/winex11.so "$U/winex11.so"
  sha256sum "$U/winex11.so"
  mark winex11
else echo "already done"; fi

# ---------------------------------------------------------------------------------------------
step "Building the patched Mesa $MESA_VER into $STW/mesa-patched (about 20 minutes)"
if ! done_ mesa; then
  fetch "$MESA_URL" "$MESA_SHA"
  rm -rf "$STW/build/mesa-$MESA_VER"
  tar -xJf "$DL/mesa-$MESA_VER.tar.xz" -C "$STW/build"
  cd "$STW/build/mesa-$MESA_VER/src/gallium/drivers/v3d"
  patch -p1 --dry-run < "$STW/patches/mesa-v3d-busy-range.patch" >/dev/null || die "the Mesa patch does not apply."
  patch -p1 < "$STW/patches/mesa-v3d-busy-range.patch"
  cd "$STW/build/mesa-$MESA_VER"
  rm -rf "$STW/mesa-patched"
  meson setup _build -Dprefix="$STW/mesa-patched" -Dbuildtype=release \
    -Dgallium-drivers=v3d,vc4 -Dvulkan-drivers= -Dplatforms=x11,wayland -Dglx=dri \
    -Degl=enabled -Dgbm=enabled -Dgles1=disabled -Dgles2=enabled -Dglvnd=enabled \
    -Dllvm=disabled -Dvideo-codecs= -Dgallium-va=disabled -Dlmsensors=disabled \
    -Dvalgrind=disabled -Dlibunwind=disabled
  ninja -C _build -j "$JOBS"
  ninja -C _build install
  [ -f "$STW/mesa-patched/share/glvnd/egl_vendor.d/50_mesa.json" ] || die "patched Mesa did not install where the profiles expect it."
  mark mesa
else echo "already done"; fi

# ---------------------------------------------------------------------------------------------
step "Unpacking the game into $STW/game-lazy (innoextract, no emulation)"
if [ -f "$STW/game-lazy/ShogunM.exe" ]; then
  echo "game-lazy already present: kept (saves and settings stay)."
else
  hash_installer
  rm -rf "$STW/game.x"
  innoextract --gog --language=en-US -d "$STW/game.x" "$EXE"
  mkdir -p "$STW/installer-extras"
  for d in __redist tmp commonappdata; do
    [ -e "$STW/game.x/$d" ] && rm -rf "$STW/installer-extras/$d" && mv "$STW/game.x/$d" "$STW/installer-extras/"
  done
  [ -d "$STW/game.x/app" ] && cp -a "$STW/game.x/app/." "$STW/game.x/" && rm -rf "$STW/game.x/app"
  [ -f "$STW/game.x/ShogunM.exe" ] || die "ShogunM.exe not found after unpacking."
  mv "$STW/game.x" "$STW/game-lazy"
fi

# ---------------------------------------------------------------------------------------------
step "Adding the d3d9lazy shim and dsound.dll to the game folder; Wine prefix"
cd "$STW/tools/d3d9lazy"
i686-w64-mingw32-gcc -O2 -msse2 -shared -o d3d9.dll d3d9lazy.c -Wl,--kill-at -static-libgcc
cp d3d9.dll "$STW/game-lazy/d3d9.dll"
cp "$STW/tools/dsound/dsound-native.dll" "$STW/game-lazy/dsound.dll"
sha256sum "$STW/game-lazy/d3d9.dll" "$STW/game-lazy/dsound.dll"
set -a
. "$STW/config/pi4-stw-lazy.env"
. "$STW/config/track-box64.env"
set +a
export DISPLAY="${DISPLAY:-:0}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export WINEPREFIX WINEDEBUG=fixme-all
if [ -f "$WINEPREFIX/system.reg" ]; then
  echo "Wine prefix already present: kept ($WINEPREFIX)."
else
  echo "Creating the Wine prefix (a few minutes)..."
  WINEDLLOVERRIDES="mscoree=;mshtml=" $WINE_CMD wineboot -u || true
  $WINESERVER_CMD -w
  [ -f "$WINEPREFIX/system.reg" ] || die "the Wine prefix was not created ($WINEPREFIX)."
fi

# ---------------------------------------------------------------------------------------------
step "Adding the shortcuts"
# The icon is made from the game's own icon (a game file, so it is not shipped with the project).
ICO=$(ls "$STW"/game-lazy/goggame-*.ico 2>/dev/null | head -1)
if [ ! -f "$STW/config/desktop/shogun.png" ] && [ -n "$ICO" ]; then
  convert "${ICO}[4]" "$STW/config/desktop/shogun.png" ||
    echo "NOTE: could not make the shortcut icon (not needed to play)."
fi
install_shortcuts
write_installed

printf '\n==> Done\n'
cat <<EOF
Start the game with the "Shogun Total War" shortcut, or:
  $STW/scripts/pi/play.sh            full screen (default)
  $STW/scripts/pi/play.sh --fps      with a frame-rate counter
  $STW/scripts/pi/play.sh --window   in an 800x600 Wine desktop window
The first start takes longer. In the game, a 16:9 battle resolution (Options > Video) fills the
screen without stretching. This log: $LOG
EOF
