# Sudden Strike 2 on a Raspberry Pi 4

Runs the GOG release of **Sudden Strike 2** (product `1443986935`) on a Raspberry Pi 4 through
Hangover 11.16 with its FEX x86 emulator and cnc-ddraw. **You need your own copy of the game**
(GOG offline installer); nothing from the game is in this repository and the game executable is
not modified.

Measured on a Pi 4 (4 GB): about 60 FPS in a mission (59.7 average / 51.7 minimum) at a true
1280x720 with the widescreen patch. Saving and loading work.

**Sudden Strike: Resource War** used to be in this folder. Since wrapper 1.0.0 it has its own:
[games/sudden-strike-resource-war](../sudden-strike-resource-war/).

## Setup

On the Pi (64-bit Raspberry Pi OS / Debian 13 "trixie"), from a copy of this folder, with your
GOG offline installer `setup_sudden_strike_2_2.2_(13718).exe` in a folder such as `~/gog`:

```sh
scripts/pi/setup.sh --installer ~/gog
```

It installs `innoextract`, `unzip` and `curl` if missing, and Hangover 11.16 with its FEX
back-end (`hangover-wine`, `hangover-libwow64fex`) from the official release if they are not
installed (apt is simulated first; it stops if any installed package would be upgraded or
removed, unless you add `--allow-upgrades`). It then sets the game up in `~/ss2` (`--home DIR`
for another place): extracts the installer (keeping a hard-linked clean copy
`game-ss2.pristine`), applies GOG's `winmm_override` music files, sets 800x600, installs
cnc-ddraw, creates the Wine prefix and adds a **Sudden Strike 2** shortcut (app menu, and the
desktop if `~/Desktop` exists; `--no-desktop` skips it). A second run resumes where it stopped.
`--check` runs only the checks and changes nothing; exit code 3 means it stopped on something
you have to fix (the message starts with `NEEDS YOU:`). Tested GOG build and file hashes are in
[game.json](game.json).

**Do not switch to Hangover's default WowBox64 back-end:** saving hangs forever under it.

### Widescreen (optional)

The 60 FPS figure above is at a true 1280x720 with St1cky's SS2 Multi Resolution Patcher, a
closed-source community tool that is not included and not run by the setup. If you have it, run
it on copies inside `scripts/pi/sandbox.sh`, put its output in `~/ss2/widescreen/1280x720/` and
run `scripts/pi/apply-widescreen.sh install` (again after any later `install-cnc-ddraw.sh`).
Without it the game runs at 800x600 stretched to the screen.

| File | Purpose |
|---|---|
| `scripts/pi/setup.sh` | Whole setup (see above) |
| `scripts/pi/play.sh [--fps] [--fit\|--window]` | Starts the game; used by the desktop shortcut |
| `scripts/pi/install-cnc-ddraw.sh` | Downloads cnc-ddraw 7.1.0.0 from its GitHub release (SHA-256 checked) and installs it into the game folder with `config/cnc-ddraw/ddraw.ini` |
| `scripts/pi/apply-widescreen.sh install\|remove` | Switches the game to the patched 1280x720 files |
| `scripts/pi/sandbox.sh` | Runs the closed-source community resolution patcher in a sandbox (the patcher is not included) |
| `config/pi4-ss2.env` | Device and game settings (game folder, executable) |
| `config/track-hangover.env` | Hangover paths, own prefix `~/ss2/prefixes/hangover`, FEX back-end |
| `config/profile-play.env` | Profile used by `play.sh` |
| `config/desktop/Sudden-Strike-2.desktop` | Shortcut template (`@GAME_HOME@` is filled in by the setup) |
| `docs/game-files-pi4.md` | How the installer is extracted with `innoextract`, and the GOG `winmm_override` step |

## Upgrading from 0.9.0

0.9.0 kept Resource War in `~/ss2/game-rw` and started it with `play.sh rw`. To move it, follow
[games/sudden-strike-resource-war](../sudden-strike-resource-war/README.md#moving-from-sudden-strike-2-090);
`play.sh rw` now only prints where it went. `play.sh ss2` still works (the `ss2` is ignored).

## License

The scripts, configuration and docs here are MIT ([LICENSE](../../LICENSE)). cnc-ddraw (MIT),
Hangover/Wine (LGPL 2.1+) and FEX (MIT) keep their own licenses and are downloaded, not stored
here. Sudden Strike 2 is a commercial game and is not included.
