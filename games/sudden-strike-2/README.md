# Sudden Strike 2 on a Raspberry Pi 4

Runs the GOG release of **Sudden Strike 2** (product `1443986935`) on a Raspberry Pi 4 through
Hangover 11.16 with its FEX x86 emulator and cnc-ddraw. **You need your own copy of the game**
(GOG offline installer); nothing from the game is in this repository and the game executable is
not modified.

Measured on a Pi 4 (4 GB): about 60 FPS in a mission (59.7 average / 51.7 minimum) at a true
1280x720 with the widescreen patch. Saving and loading work.

**Sudden Strike: Resource War** used to be in this folder. Since wrapper 1.0.0 it has its own:
[games/sudden-strike-resource-war](../sudden-strike-resource-war/).

## Status: wrapper 1.0.0, no new-Pi setup script yet

These files reproduce the working setup on the Pi it was made on. There is **no setup script
yet**, so a new Pi needs the steps below by hand. Tested GOG build and file hashes are in
[game.json](game.json).

| File | Purpose |
|---|---|
| `scripts/pi/play.sh [--fps] [--fit\|--window]` | Starts the game; used by the desktop shortcut |
| `scripts/pi/install-cnc-ddraw.sh` | Downloads cnc-ddraw 7.1.0.0 from its GitHub release (SHA-256 checked) and installs it into the game folder with `config/cnc-ddraw/ddraw.ini` |
| `scripts/pi/apply-widescreen.sh install\|remove` | Switches the game to the patched 1280x720 files |
| `scripts/pi/sandbox.sh` | Runs the closed-source community resolution patcher in a sandbox (the patcher is not included) |
| `config/pi4-ss2.env` | Device and game settings (game folder, executable) |
| `config/track-hangover.env` | Hangover paths, own prefix `~/ss2/prefixes/hangover`, FEX back-end |
| `config/profile-play.env` | Profile used by `play.sh` |
| `config/desktop/Sudden-Strike-2.desktop` | Desktop shortcut (points at `/home/admin/ss2`; change the path for another user) |
| `docs/game-files-pi4.md` | How the installer is extracted with `innoextract`, and the GOG `winmm_override` step |

## Manual setup outline

1. Hangover 11.16 installed system-wide **including the `hangover-libwow64fex` package**.
   Medieval: Total War's [setup-new-pi.sh](../medieval-total-war/scripts/pi/setup-new-pi.sh)
   installs Hangover but not that FEX package (it ships in the same Hangover release tarball).
2. Copy this folder to `~/ss2`, put the installer in `~/ss2/installer/`, extract it and apply
   the `winmm_override` files as in [docs/game-files-pi4.md](docs/game-files-pi4.md).
3. `scripts/pi/install-cnc-ddraw.sh`, then optionally the widescreen step (run
   `apply-widescreen.sh install` again after any later `install-cnc-ddraw.sh`).
4. Copy the `.desktop` file to `~/Desktop`.

**Do not switch to Hangover's default WowBox64 back-end:** saving hangs forever under it.

## Upgrading from 0.9.0

0.9.0 kept Resource War in `~/ss2/game-rw` and started it with `play.sh rw`. To move it, follow
[games/sudden-strike-resource-war](../sudden-strike-resource-war/README.md#moving-from-sudden-strike-2-090);
`play.sh rw` now only prints where it went. `play.sh ss2` still works (the `ss2` is ignored).

## License

The scripts, configuration and docs here are MIT ([LICENSE](../../LICENSE)). cnc-ddraw (MIT),
Hangover/Wine (LGPL 2.1+) and FEX (MIT) keep their own licenses and are downloaded, not stored
here. Sudden Strike 2 is a commercial game and is not included.
