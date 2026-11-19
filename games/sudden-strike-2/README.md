# Sudden Strike 2 + Sudden Strike: Resource War on a Raspberry Pi 4

Runs the GOG releases of **Sudden Strike 2** (product `1443986935`) and **Sudden Strike:
Resource War** (product `1707288232`) on a Raspberry Pi 4 through Hangover 11.16 with its FEX
x86 emulator and cnc-ddraw. **You need your own copy of the games** (GOG offline installers);
nothing from the games is in this repository and the game executables are not modified.

Measured on a Pi 4 (4 GB): about 60 FPS in Sudden Strike 2 missions (true 1280x720 with the
widescreen patch), 55 average / 44 minimum in Resource War (800x600 stretched to full screen).
Saving and loading work in both.

## Status: wrapper 0.9.0, no new-Pi setup script yet

These files reproduce the working setup on the Pi it was made on. There is **no
`setup-new-pi.sh` yet**, so a new Pi needs the steps below by hand. Tested GOG builds and file
hashes are in [game.json](game.json).

| File | Purpose |
|---|---|
| `scripts/pi/play.sh ss2\|rw [--fps] [--fit\|--window]` | Starts a game; used by the desktop shortcuts |
| `scripts/pi/install-cnc-ddraw.sh` | Downloads cnc-ddraw 7.1.0.0 from its GitHub release and installs it into both game folders with `config/cnc-ddraw/ddraw.ini` |
| `scripts/pi/apply-widescreen.sh install\|remove` | Switches Sudden Strike 2 to the patched 1280x720 files |
| `scripts/pi/sandbox.sh` | Runs the closed-source community resolution patcher in a sandbox (the patcher is not included) |
| `config/pi4-ss2.env`, `config/pi4-rw.env` | Per-game device settings (game folder, executable) |
| `config/track-hangover.env` | Hangover paths, own prefix `~/ss2/prefixes/hangover`, FEX back-end |
| `config/profile-play.env` | Profile used by `play.sh` |
| `config/desktop/*.desktop` | Desktop shortcuts (they point at `/home/admin/ss2`; change the path for another user) |
| `docs/game-files-pi4.md` | How the installers are extracted with `innoextract`, and the GOG `winmm_override` step for Sudden Strike 2 |

## Manual setup outline

1. Hangover 11.16 installed system-wide **including the `hangover-libwow64fex` package**.
   Medieval: Total War's [setup-new-pi.sh](../medieval-total-war/scripts/pi/setup-new-pi.sh)
   installs Hangover but not that FEX package (it ships in the same Hangover release tarball);
   on the original Pi it was installed during Medieval's experiments.
2. Copy this folder to `~/ss2`, put the installers in `~/ss2/installer/`, extract them and apply
   the `winmm_override` files as in [docs/game-files-pi4.md](docs/game-files-pi4.md).
3. `scripts/pi/install-cnc-ddraw.sh`, then optionally the widescreen step.
4. Copy the `.desktop` files to `~/Desktop`.

**Do not switch to Hangover's default WowBox64 back-end:** saving hangs forever under it.

## License

The scripts, configuration and docs here are MIT ([LICENSE](../../LICENSE)). cnc-ddraw (MIT),
Hangover/Wine (LGPL 2.1+) and FEX (MIT) keep their own licenses and are downloaded, not stored
here. Sudden Strike 2 and Resource War are commercial games and are not included.
