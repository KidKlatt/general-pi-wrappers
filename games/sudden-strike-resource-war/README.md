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

## Status: wrapper 1.0.0, no new-Pi setup script yet

These files reproduce the working setup on the Pi it was made on. There is **no setup script
yet**, so a new Pi needs the steps below by hand. Tested GOG build and file hashes are in
[game.json](game.json).

| File | Purpose |
|---|---|
| `scripts/pi/play.sh [--fps] [--fit\|--window]` | Starts the game; used by the desktop shortcut |
| `scripts/pi/install-cnc-ddraw.sh` | Downloads cnc-ddraw 7.1.0.0 from its GitHub release (SHA-256 checked) and installs it into the game folder with `config/cnc-ddraw/ddraw.ini` |
| `config/pi4-ssrw.env` | Device and game settings (game folder `game`, executable) |
| `config/track-hangover.env` | Hangover paths, own prefix `~/ssrw/prefixes/hangover`, FEX back-end |
| `config/profile-play.env` | Profile used by `play.sh` |
| `config/desktop/Sudden-Strike-Resource-War.desktop` | Desktop shortcut (points at `/home/admin/ssrw`; change the path for another user) |
| `docs/game-files-pi4.md` | How the installer is extracted with `innoextract` |

## Manual setup outline

1. Hangover 11.16 installed system-wide **including the `hangover-libwow64fex` package**.
   Medieval: Total War's [setup.sh](../medieval-total-war/scripts/pi/setup.sh)
   installs Hangover but not that FEX package (it ships in the same Hangover release tarball).
   `curl`, `unzip` and `innoextract` from apt.
2. Copy this folder to `~/ssrw`, put the installer in `~/ssrw/installer/` and extract it to
   `~/ssrw/game` as in [docs/game-files-pi4.md](docs/game-files-pi4.md); set `VideoMode=2` in
   `game/sudtest.ini`.
3. `scripts/pi/install-cnc-ddraw.sh`.
4. Create the prefix: `WINEPREFIX=~/ssrw/prefixes/hangover WINEARCH=win64 wineboot -i`.
5. Copy the `.desktop` file to `~/Desktop`.

**Do not switch to Hangover's default WowBox64 back-end:** saving hangs forever under it.

## Moving from Sudden Strike 2 0.9.0

Wrapper 0.9.0 of `sudden-strike-2` kept this game in `~/ss2/game-rw`. With no game running:

```sh
mkdir -p ~/ssrw/installer          # then copy this folder's scripts/ and config/ into ~/ssrw
mv ~/ss2/game-rw ~/ssrw/game
mv ~/ss2/game-rw.pristine ~/ssrw/game.pristine
mv ~/ss2/installer/setup_sudden_strike_resource_war_*.exe ~/ssrw/installer/
~/ssrw/scripts/pi/install-cnc-ddraw.sh
WINEPREFIX=~/ssrw/prefixes/hangover WINEARCH=win64 wineboot -i
cp ~/ssrw/config/desktop/Sudden-Strike-Resource-War.desktop ~/Desktop/
rm -f ~/ss2/config/pi4-rw.env
```

Saves live inside the game folder (`plr/savegames/`) and move with it.

## License

The scripts, configuration and docs here are MIT ([LICENSE](../../LICENSE)). cnc-ddraw (MIT),
Hangover/Wine (LGPL 2.1+) and FEX (MIT) keep their own licenses and are downloaded, not stored
here. Sudden Strike: Resource War is a commercial game and is not included.
