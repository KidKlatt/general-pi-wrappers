# Shogun: Total War – Warlord Edition on a Raspberry Pi 4

Runs the GOG release of **Shogun: Total War – Warlord Edition** (product `1874325037`, base game
and Mongol Invasion) on a Raspberry Pi 4 through Box64 and an x86-64 Wine 9.17 in WoW64 mode.
**You need your own copy of the game** (GOG offline installer); nothing from the game is in this
repository and the game executable is not modified.

Measured on a Pi 4 (4 GB), full screen: 35–37 average / 24–28 minimum FPS while armies fight
(three 15-minute test runs, never below 15 FPS, at most 56 °C), about 35 on the campaign map,
55–60 in menus. Campaigns, custom and historical battles, and save/load work.

## Status: wrapper 1.0.0, playable

Set up on a new Pi with one script, then play from the desktop shortcut. The setup is
standalone: Box64, Wine, Mesa and the DLLs are downloaded from their official sources (pinned
SHA-256) or built on the Pi into `~/stw`; nothing from another game's setup is used. Still open:
a sound check on better speakers (sound plays; the development Pi's small speakers sounded poor).
Tested GOG build and file hash are in [game.json](game.json).

**Set it up:** [docs/NEW-PI-SETUP.md](docs/NEW-PI-SETUP.md). **Versions, rebuild, uninstall:**
[docs/RUNBOOK.md](docs/RUNBOOK.md).

| File | Purpose |
|---|---|
| `scripts/pi/setup.sh` | Whole setup on a new Pi: apt packages (simulated first), Box64 from source, Kron4ek Wine 9.17, own `dsound.dll` and `winex11.so` from the Wine source, patched Mesa, game from your installer, shim, prefix, shortcuts |
| `scripts/pi/play.sh` | Launcher: full screen (default), `--fps` counter, `--window` (800x600 Wine desktop) |
| `scripts/pi/uninstall.sh` | Removes the game home (game, saves, Wine prefix) and its shortcuts; asks first (`--check` only lists, `--yes` skips the question); apt packages stay |
| `config/desktop/*.desktop` | Desktop shortcuts (normal and with FPS counter); the icon is made from the game's own icon during setup |
| `config/track-box64.env` | Box64 + Wine 9.17 paths, own prefix `~/stw/prefixes/box64`, own caches |
| `config/pi4-stw-lazy.env` | Device settings for the game copy `~/stw/game-lazy` that holds the custom DLLs |
| `config/profile-play.env` | The final profile: full screen, d3d9lazy and dsound overrides, patched Mesa paths |
| `config/profile-window.env` | The same in an 800x600 Wine desktop window (`play.sh --window`) |
| `tools/d3d9lazy/d3d9lazy.c` | Own Direct3D 9 shim (Medieval's v10 plus a per-frame draw gate), built with MinGW as `d3d9.dll` |
| `tools/dsound/` | Patch for Wine 9.17's DirectSound with a linear resampler (fixed the battle slowdowns) |
| `tools/winex11/` | Two changes to Wine 9.17's `winex11.so`: removes a deadlock at campaign start, and sets Xwayland emulated modes so the game fills the screen |
| `patches/mesa-v3d-busy-range.patch` | Mesa 26.2.6 patch for the Pi 4's V3D (same as Medieval: Total War's) |
| `docs/game-files-pi4.md` | How the installer is extracted with `innoextract` and what the game folder contains |

The DLLs are built on the Pi from these patches and the official sources; no built binaries
are stored here.

## License

The scripts, configuration, docs and shim source here are MIT ([LICENSE](../../LICENSE)). The
patches and the `apply-*.py` scripts under `tools/dsound/` and `tools/winex11/` modify Wine and
carry excerpts of its source, so they fall under Wine's LGPL 2.1+; the Mesa patch under
`patches/` under Mesa's license (mainly MIT). Box64 (MIT), Wine (LGPL 2.1+) and Mesa (mainly MIT)
keep their own licenses and are downloaded, not stored here. Shogun: Total War is a commercial
game and is not included. See [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) for every
component, what is built on the Pi, and what goes into the game folder.
