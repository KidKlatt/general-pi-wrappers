# Third-party software and content

The MIT license in [LICENSE](../../LICENSE) covers only this project's own work: the scripts, the
configuration files, the documentation, the d3d9lazy shim source in `tools/d3d9lazy/` and
`tools/winex11/mkcross.sh`.

This project mostly glues together other people's work, and that work keeps its own license.
**Check the license of each project below yourself before you reuse, modify or redistribute
anything.** The summaries here are a pointer, not legal advice, and licenses can change between
versions.

## Downloaded or installed by the setup script (not stored in this repo)

`scripts/pi/setup.sh` pins each download and checks its SHA-256.

| Component | Where it comes from | License (check the source) |
|---|---|---|
| Box64, commit `a46caf3` (0.4.5 development) | https://github.com/ptitSeb/box64 (cloned and built on the Pi) | MIT. The setup copies Box64's `LICENSE` to `~/stw/box64/usr/doc/box64/`. |
| x86-64 libraries in Box64's `x64lib/` (libstdc++, libgcc_s, libpng12, libunwind, OpenSSL 1.0/1.1, mbedTLS) | Part of the Box64 source above; the setup copies them to `~/stw/box64/usr/lib/box64-x86_64-linux-gnu/` | Each library keeps its own license (for example GCC Runtime Library Exception, libpng, OpenSSL, Apache 2.0). See those projects. |
| Wine 9.17, x86-64 WoW64 build by Kron4ek | https://github.com/Kron4ek/Wine-Builds (release `9.17`, `wine-9.17-amd64-wow64.tar.xz`) | Wine is LGPL 2.1 or later; Kron4ek's build scripts are MIT. The archive also carries libraries with their own licenses. |
| Wine 9.17 source | https://dl.winehq.org/wine/source/9.x/ | LGPL 2.1 or later (Wine's `LICENSE` and `COPYING.LIB`). |
| Mesa 26.2.6 source | https://archive.mesa3d.org | Mainly MIT; some parts use other licenses. See Mesa's `docs/license.rst`. |
| Debian / Raspberry Pi OS packages (innoextract, the MinGW-w64 and x86-64 cross compilers, CMake, Meson, X11/xcb/Wayland development files, ImageMagick, zenity, xdotool, grim, etc.) | apt | Each package's license is in `/usr/share/doc/<package>/copyright` on the Pi. |

## Stored in this repo but not covered by the MIT license

| Path | What it is | License |
|---|---|---|
| `tools/dsound/wine-9.17-dsound-linear.patch`, `tools/dsound/apply-linear.py` | Changes to Wine's DirectSound source (`dlls/dsound/mixer.c`); the script contains excerpts of that Wine source | A modification of Wine, so LGPL 2.1 or later. |
| `tools/winex11/wine-9.17-winex11-gl-nolock.patch`, `tools/winex11/apply-gl-nolock.py`, `tools/winex11/apply-xwayland-modeset.py` | Changes to Wine's X11 driver source (`dlls/winex11.drv`); the scripts contain excerpts of that Wine source | A modification of Wine, so LGPL 2.1 or later. |
| `patches/mesa-v3d-busy-range.patch` | Changes to Mesa's V3D driver source | A modification of Mesa, so it falls under Mesa's license for those files. |

## Built on your Pi

The setup builds these in `~/stw` from the sources above. They never leave the Pi:

- `box64` from the Box64 source.
- `dsound.dll` (copied into the game folder) and `winex11.so` (replacing the one in the Kron4ek
  Wine copy, whose original is kept as `winex11.so.kron4ek`), built from the Wine 9.17 source
  with this project's changes. Both are modified Wine, so LGPL 2.1 or later.
- Mesa in `~/stw/mesa-patched`, with the patch above.
- The d3d9lazy shim `d3d9.dll` (this project's own code). It links the GCC runtime statically
  (`-static-libgcc`), which the GCC Runtime Library Exception allows.
- The x86-64 link stubs from `tools/winex11/mkcross.sh`: empty libraries carrying only the
  function names of the Pi's own X11, GL and Vulkan libraries, used to link `winex11.so` and
  never loaded.

If you copy a set-up game home or a disk image to someone else, you are distributing these
binaries (and the game, which you may not). Wine's LGPL then requires that you also offer the
matching source, including this project's patches.

## Changes to the game folder

The game's own files are not modified. The setup adds `d3d9.dll` (d3d9lazy) and `dsound.dll`
(the Wine build above) next to `ShogunM.exe`, and leaves GOG's own `ddraw.dll` proxy in place.
The shortcut icon is converted on the Pi from the game's own `goggame-*.ico`, so no game artwork
is stored in this repo.

## The game

**Shogun: Total War – Warlord Edition** is a commercial game by The Creative Assembly, first
published by Electronic Arts and now SEGA, and sold by GOG. It is **not** included here and must
be bought separately. The setup only unpacks your own copy of the GOG offline installer.
"Shogun: Total War" and "Total War" are trademarks of their owners. This project is not
affiliated with or endorsed by them.
