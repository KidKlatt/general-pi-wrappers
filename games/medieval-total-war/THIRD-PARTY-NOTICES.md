# Third-party software and content

The MIT license in [LICENSE](../../LICENSE) covers only this project's own work: the scripts, the
configuration files, the documentation and the d3d9lazy shim source in `tools/d3d9lazy/`.

This project mostly glues together other people's work, and that work keeps its own license.
**Check the license of each project below yourself before you reuse, modify or redistribute
anything.** The summaries here are a pointer, not legal advice, and licenses can change between
versions.

## Downloaded or installed by the setup script (not stored in this repo)

Each download is pinned and its SHA-256 checked.

| Component | Where it comes from | License (check the source) |
|---|---|---|
| Hangover 11.16 (`hangover-wine`, `hangover-wowbox64`, `hangover-libarm64ecfex`) | https://github.com/AndreRH/hangover (official release), installed with apt, or unpacked into `~/mtw/hangover` with `--private-wine` | Hangover and its Wine are LGPL 2.1 or later; the WowBox64 back-end comes from Box64 (MIT); FEX is MIT. See the Hangover repository. |
| Mesa 26.2.6 source | https://archive.mesa3d.org | Mainly MIT; some parts use other licenses. See Mesa's `docs/license.rst`. |
| Debian / Raspberry Pi OS packages (innoextract, MinGW-w64 cross compiler, Mesa build tools, etc.) | apt | Each package's license is in `/usr/share/doc/<package>/copyright` on the Pi. |

## Stored in this repo but not covered by the MIT license

| Path | What it is | License |
|---|---|---|
| `patches/mesa-v3d-busy-range.patch` | Changes to Mesa's V3D driver source | A modification of Mesa, so it falls under Mesa's license for those files. |

## Built on your Pi

The setup builds these in `~/mtw` from the sources above. They never leave the Pi:

- Mesa in `~/mtw/mesa-patched`, with the patch above.
- The d3d9lazy shim `d3d9.dll` (this project's own code). It links the GCC runtime statically
  (`-static-libgcc`), which the GCC Runtime Library Exception allows.

If you copy a set-up game home or a disk image to someone else, you are distributing these
binaries, Hangover with `--private-wine`, and the game, which you may not.

## Changes to the game folder

The game's own files are not modified. The setup adds `d3d9.dll` (d3d9lazy) next to
`Medieval_TW.exe`.

## The game

**Medieval: Total War** is a commercial game by The Creative Assembly, published by Activision
and now SEGA, and sold by GOG. It is **not** included here and must be bought separately. The
setup only unpacks your own copy of the GOG offline installer. "Medieval: Total War" and
"Total War" are trademarks of their owners. This project is not affiliated with or endorsed by
them.
