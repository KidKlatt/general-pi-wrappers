# Runbook: Shogun: Total War on the Pi 4

What runs, which exact versions, how to rebuild it, and how to remove all of it. The project is
standalone: nothing under `~/mtw`, `~/ss2` or any other game folder is used at run time or at
build time (checked 2026-11-18, see "Standalone check").

## Play

| | |
|---|---|
| Shortcuts | `Shogun-Total-War.desktop` (full screen), `Shogun-Total-War-FPS.desktop` (with FPS counter), in the app menu (`~/.local/share/applications`) and on the desktop if `~/Desktop` exists |
| Command | `~/stw/scripts/pi/play.sh [--fps] [--window]` |
| Logs | `~/stw/logs/play-*.log` |
| Saves | `~/stw/game-lazy/savegames/*.cpg` |

`play.sh` refuses to start if Shogun already runs; other games may run at the same time (on a
4 GB Pi both slow down). Full screen is Xwayland's mode emulation: the game's 800x600 / 640x480 screens are stretched
to the 16:9 display; a 16:9 battle resolution chosen in the game (Options > Video) fills it
without stretching. `--window` runs the game in an 800x600 Wine desktop window instead (the test
harness's mode).

## Components and versions

Everything lives in `~/stw` (`STW_HOME`). Built or fetched by `scripts/pi/setup.sh`.

| Component | Where | Version / source | Check |
|---|---|---|---|
| Box64 | `~/stw/box64/usr/local/bin/box64` + `usr/lib/box64-x86_64-linux-gnu` | built from github.com/ptitSeb/box64 commit `a46caf3b0bf885b563473ee8818df2e05e4c47e7` (0.4.5 development, 2026-11-14), `-DRPI4ARM64=1 -DCMAKE_BUILD_TYPE=RelWithDebInfo`; x86-64 libraries from its `x64lib/` | `box64 --version` |
| Wine | `~/stw/wine-x64-9.17` | Kron4ek `wine-9.17-amd64-wow64.tar.xz`, SHA-256 `684c8fe59fc27e339115e57c4a50484d895f8557e9b084d520fde0a33253fdf9` | `bin/wine --version` = `wine-9.17` |
| winex11.so (own) | `~/stw/wine-x64-9.17/lib/wine/x86_64-unix/winex11.so` | Wine 9.17 source + `tools/winex11/apply-gl-nolock.py` (campaign-start hang fix) + `apply-xwayland-modeset.py` (full screen); x86-64 cross build; original kept as `winex11.so.kron4ek` | log line `STW winex11 build` |
| dsound.dll (own) | `~/stw/game-lazy/dsound.dll` | Wine 9.17 source + `tools/dsound/apply-linear.py` (linear resampler), builtin marker blanked | log line `STW dsound build: linear resampler` |
| d3d9 shim (own) | `~/stw/game-lazy/d3d9.dll` | `tools/d3d9lazy/d3d9lazy.c`, `i686-w64-mingw32-gcc -O2 -msse2 -shared -Wl,--kill-at -static-libgcc` | `d3d9lazy.log` in the game folder |
| Wine source | `~/stw/src/wine-9.17` | `dl.winehq.org/wine/source/9.x/wine-9.17.tar.xz`, SHA-256 `3edb7eb6f31bb5c3f7378dd5623da9d95f7d4d6d7c8378afd89c8e3a30aa080c` | |
| Patched Mesa | `~/stw/mesa-patched` | Mesa 26.2.6 (`archive.mesa3d.org`, SHA-256 `b9436b3e1a8be76fbd4823dc884f90596ab7c6ac5e1867a305e66ffccfb31a92`) + `patches/mesa-v3d-busy-range.patch`; only the game uses it (env vars in the profile), the system Mesa is untouched | `grep libgallium /proc/$(pgrep -x ShogunM.exe)/maps` |
| Game | `~/stw/game-lazy` | GOG `setup_shogun_total_wartm_gog_v1_(86790).exe`, SHA-256 `bed36e39c45bc447f21a25c7de5f3f09a09587ac176129cd3621fe9c5f216b28`, unpacked with `innoextract --gog --language=en-US` | `ShogunM.exe` |
| Wine prefix | `~/stw/prefixes/box64` | `wineboot -u`; no registry changes | |
| Settings | `config/pi4-stw-lazy.env` + `config/track-box64.env` + `config/profile-play.env` | | |

Exact SHA-256 of the built files are printed in the setup log (`~/stw/logs/setup-*.log`).

## Rebuild or set up again

```sh
tmux new -s stw
~/stw/scripts/pi/setup.sh --installer ~/stw/installer
```

Each step leaves a marker in `~/stw/.setup/`; delete a marker (for example `mesa.done`) to redo
that step. The game folder and the Wine prefix are kept if present. A new Pi: see
[NEW-PI-SETUP.md](NEW-PI-SETUP.md).

## apt packages

The setup script installs these if missing (simulated first; it stops if anything would be
upgraded or removed): `innoextract xdotool grim imagemagick zenity tmux curl ca-certificates
xz-utils patch git cmake python3 gcc g++ make flex bison gcc-mingw-w64-i686 gcc-x86-64-linux-gnu
libc6-dev-amd64-cross`, X development headers (`libx11-dev libxext-dev libxrender-dev
libxrandr-dev libxfixes-dev libxxf86vm-dev libxi-dev libxinerama-dev libxcursor-dev
libxcomposite-dev libgl-dev`) and the Mesa build dependencies (`meson ninja-build pkg-config
python3-mako python3-yaml python3-packaging python3-ply libdrm-dev libexpat1-dev zlib1g-dev
libzstd-dev libxcb-*-dev libx11-xcb-dev libxshmfence-dev libwayland-dev wayland-protocols
libwayland-egl-backend-dev libglvnd-dev libglvnd-core-dev`). None is needed to *play*; they are
for building.

On the development Pi, which already had most of them from the other projects, this project
alone installed (apt history, 2026-11-18): `gcc-x86-64-linux-gnu` (+19 automatic `*-amd64-cross`
/ `*-x86-64-linux-gnu` packages), `libc6-dev-amd64-cross` (+`linux-libc-dev-amd64-cross`),
`libxi-dev libxinerama-dev libxcursor-dev libxcomposite-dev`, `cmake` (+`cmake-data librhash1`).

## Uninstall

```sh
# 1. stop the game if it runs (this project's prefix only)
WINEPREFIX=~/stw/prefixes/box64 ~/stw/box64/usr/local/bin/box64 ~/stw/wine-x64-9.17/bin/wineserver -k
# 2. everything of this project
rm -rf ~/stw
rm -f ~/Desktop/Shogun-Total-War*.desktop ~/.local/share/applications/Shogun-Total-War*.desktop
# 3. optional: build packages this project alone installed (check nothing else needs them)
sudo apt-get remove gcc-x86-64-linux-gnu libc6-dev-amd64-cross libxi-dev libxinerama-dev \
  libxcursor-dev libxcomposite-dev cmake
```

Avoid `apt autoremove` if the Pi does other jobs: it can remove packages other software still
relies on. Remove the automatic cross packages by name if wanted. Nothing else on the system is
changed: no registry or file outside `~/stw` and the two shortcuts, no service, no CPU weight.

## Standalone check

With the game running, no file from another project may be open or mapped:

```sh
pid=$(pgrep -x ShogunM.exe); for p in $pid $(pgrep -f wineserver); do grep -h -E '/home/[^/]+/(mtw|ss2)/' /proc/$p/maps; done; ls -l /proc/$pid/fd | grep -E '/(mtw|ss2)/'
```

Both must print nothing. `grep -rn 'HOME/mtw\|/mtw/' ~/stw/config ~/stw/scripts` must find only
comments.
