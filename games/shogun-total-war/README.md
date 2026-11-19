# Shogun: Total War – Warlord Edition on a Raspberry Pi 4

Runs the GOG release of **Shogun: Total War – Warlord Edition** (product `1874325037`, base game
and Mongol Invasion) on a Raspberry Pi 4 through Box64 and an x86-64 Wine 9.17 in WoW64 mode.
**You need your own copy of the game** (GOG offline installer); nothing from the game is in this
repository and the game executable is not modified.

Measured on a Pi 4 (4 GB): 36.5 average / 20.5 minimum FPS in a fight, about 35 on the campaign
map, 55–60 in menus, at 800x600. Campaigns, custom and historical battles, and save/load work.

## Status: wrapper 0.9.0, work in progress

The game plays, but the hand-over parts are **not written yet**: no `play.sh`, no desktop
shortcut and no setup script. The setup also still borrows two things from the Medieval: Total
War setup on the same Pi: its patched Mesa (`~/mtw/mesa-patched`) and its Box64 0.4.5
(`~/mtw/box64`). Tested GOG build and file hash are in [game.json](game.json).

| File | Purpose |
|---|---|
| `config/track-box64.env` | Box64 + Wine 9.17 paths, own prefix `~/stw/prefixes/box64`, own caches |
| `config/pi4-stw-lazy.env` | Device settings for the game copy `~/stw/game-lazy` that holds the custom DLLs |
| `config/profile-best.env` | The working profile: d3d9lazy and dsound overrides, patched Mesa paths, 800x600 |
| `tools/d3d9lazy/d3d9lazy.c` | Own Direct3D 9 shim (Medieval's v10 plus a per-frame draw gate), built with MinGW as `d3d9.dll` |
| `tools/dsound/` | Patch for Wine 9.17's DirectSound with a linear resampler, build steps in its README (fixed the battle slowdowns) |
| `tools/winex11/` | Patch for Wine 9.17's `winex11.so` that removes a deadlock at campaign start, build steps in its README |
| `docs/game-files-pi4.md` | How the installer is extracted with `innoextract` and what the game folder contains |

The DLLs are built on the Pi from these patches and the official Wine 9.17 source; no built
binaries are stored here.

## License

The scripts, configuration, docs, shim source and patch scripts here are MIT
([LICENSE](../../LICENSE)). The patches under `tools/dsound/` and `tools/winex11/` modify Wine and
fall under Wine's LGPL 2.1+. Box64 (MIT), Wine (LGPL 2.1+) and Mesa (mainly MIT) keep their own
licenses and are downloaded, not stored here. Shogun: Total War is a commercial game and is not
included.
