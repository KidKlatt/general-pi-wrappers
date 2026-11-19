# Third-party software and content

The MIT license in [LICENSE](../../LICENSE) covers only this project's own work: the scripts, the
configuration files, the documentation and the d3d9lazy shim source in `tools/d3d9lazy/`.

This project mostly glues together other people's work, and that work keeps its own license.
**Check the license of each project below yourself before you reuse, modify or redistribute
anything.** The summaries here are a pointer, not legal advice, and licenses can change between
versions.

## Downloaded or installed by the setup script (not stored in this repo)

| Component | Where it comes from | License (check the source) |
|---|---|---|
| Hangover 11.16 | https://github.com/AndreRH/hangover (official release) | Bundles several projects with their own licenses: Wine (LGPL 2.1 or later), Box64 / WowBox64 (MIT), FEX (MIT). See the Hangover repository. |
| Mesa 26.2.6 | https://archive.mesa3d.org | Mainly MIT; some parts use other licenses. See Mesa's `docs/license.rst`. |
| Debian / Raspberry Pi OS packages (innoextract, MinGW-w64 cross compiler, Mesa build tools, etc.) | apt | Each package's license is in `/usr/share/doc/<package>/copyright` on the Pi. |

## Stored in this repo but not covered by the MIT license

| Path | What it is | License |
|---|---|---|
| `patches/mesa-v3d-busy-range.patch` | Changes to Mesa's V3D driver source | A modification of Mesa, so it falls under Mesa's license for those files. |

## The game

**Medieval: Total War** is a commercial game by The Creative Assembly, published by Activision
and now SEGA, and sold by GOG. It is **not** included here and must be bought separately. The
setup only unpacks your own copy of the GOG offline installer, and the game files are not modified.
"Medieval: Total War" and "Total War" are trademarks of their owners. This project is not
affiliated with or endorsed by them.

## Build output

The shim DLL built on the Pi links the GCC runtime statically (`-static-libgcc`). That library is
covered by the GCC Runtime Library Exception, which allows this.
