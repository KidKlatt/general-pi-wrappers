# Sudden Strike: Resource War on a Raspberry Pi 4

Runs the GOG release of **Sudden Strike: Resource War** (product `1707288232`) on a Raspberry Pi
4 through Hangover 11.16 with its FEX x86 emulator and cnc-ddraw. **You need your own copy of the
game** (GOG offline installer); nothing from the game is in this repository and the game
executable is not modified.

Measured on a Pi 4 (4 GB): 57.5 average / 50.6 minimum FPS in the first single mission, the
game's 800x600 stretched to the full 1280x720 display. Saving and loading work.

Until 2026-11-20 this game was part of [games/sudden-strike-2](../sudden-strike-2/) (wrapper
0.9.0); it uses the same engine and the same stack, without the widescreen patch (the community
patcher does not support Resource War).

## Setup

On the Pi (64-bit Raspberry Pi OS / Debian 13 "trixie"), from a copy of this folder, with your
GOG offline installer `setup_sudden_strike_resource_war_2.4_(13581).exe` in a folder such as
`~/gog`:

```sh
scripts/pi/setup.sh --installer ~/gog
```

It installs `innoextract`, `unzip` and `curl` if missing, and Hangover 11.16 with its FEX
back-end (`hangover-wine`, `hangover-libwow64fex`) from the official release if they are not
installed (apt is simulated first; it stops if any installed package would be upgraded or
removed, unless you add `--allow-upgrades`). It then sets the game up in `~/ssrw` (`--home DIR`
for another place): extracts the installer (keeping a hard-linked clean copy `game.pristine`),
sets 800x600, installs cnc-ddraw, creates the Wine prefix and adds a **Sudden Strike Resource
War** shortcut (app menu, and the desktop if `~/Desktop` exists; `--no-desktop` skips it). A
second run resumes where it stopped; a game folder or prefix that is already there is kept.
`--check` runs only the checks and changes nothing; exit code 3 means it stopped on something
you have to fix (the message starts with `NEEDS YOU:`). Tested GOG build and file hashes are in
[game.json](game.json).

**Do not switch to Hangover's default WowBox64 back-end:** saving hangs forever under it.

| File | Purpose |
|---|---|
| `scripts/pi/setup.sh` | Whole setup (see above) |
| `scripts/pi/play.sh [--fps] [--fit\|--window]` | Starts the game; used by the desktop shortcut |
| `scripts/pi/uninstall.sh` | Removes the game home (game, saves, Wine prefix) and its shortcuts; asks first (`--check` only lists, `--yes` skips the question); apt packages stay |
| `scripts/pi/install-cnc-ddraw.sh` | Downloads cnc-ddraw 7.1.0.0 from its GitHub release (SHA-256 checked) and installs it into the game folder with `config/cnc-ddraw/ddraw.ini` |
| `config/pi4-ssrw.env` | Device and game settings (game folder `game`, executable) |
| `config/track-hangover.env` | Hangover paths, own prefix `~/ssrw/prefixes/hangover`, FEX back-end |
| `config/profile-play.env` | Profile used by `play.sh` |
| `config/desktop/Sudden-Strike-Resource-War.desktop` | Shortcut template (`@GAME_HOME@` is filled in by the setup) |
| `docs/game-files-pi4.md` | How the installer is extracted with `innoextract` |

## Moving from Sudden Strike 2 0.9.0

Wrapper 0.9.0 of `sudden-strike-2` kept this game in `~/ss2/game-rw`. With no game running:

```sh
mkdir -p ~/ssrw/installer
mv ~/ss2/game-rw ~/ssrw/game
mv ~/ss2/game-rw.pristine ~/ssrw/game.pristine
mv ~/ss2/installer/setup_sudden_strike_resource_war_*.exe ~/ssrw/installer/
rm -f ~/ss2/config/pi4-rw.env
# from a copy of this folder: keeps the moved game, adds what is missing (cnc-ddraw, prefix,
# shortcut)
scripts/pi/setup.sh --installer ~/ssrw/installer
```

Saves live inside the game folder (`plr/savegames/`) and move with it.

## License

The scripts, configuration and docs here are MIT ([LICENSE](../../LICENSE)). cnc-ddraw (MIT),
Hangover/Wine (LGPL 2.1+) and FEX (MIT) keep their own licenses and are downloaded, not stored
here. Sudden Strike: Resource War is a commercial game and is not included. See
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) for what the setup installs and what it changes
in the game folder.
