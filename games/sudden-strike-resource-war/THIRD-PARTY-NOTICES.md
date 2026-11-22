# Third-party software and content

The MIT license in [LICENSE](../../LICENSE) covers only this project's own work: the scripts, the
configuration files (including `config/cnc-ddraw/ddraw.ini`) and the documentation.

This project mostly glues together other people's work, and that work keeps its own license.
**Check the license of each project below yourself before you reuse, modify or redistribute
anything.** The summaries here are a pointer, not legal advice, and licenses can change between
versions.

## Downloaded or installed by the setup script (not stored in this repo)

Each download is pinned and its SHA-256 checked.

| Component | Where it comes from | License (check the source) |
|---|---|---|
| Hangover 11.16 (`hangover-wine`, `hangover-libwow64fex`) | https://github.com/AndreRH/hangover (official release), installed with apt if missing | Hangover and its Wine are LGPL 2.1 or later; the FEX back-end is MIT. See the Hangover repository. |
| cnc-ddraw 7.1.0.0 | https://github.com/FunkyFr3sh/cnc-ddraw (official release `cnc-ddraw.zip`, by `scripts/pi/install-cnc-ddraw.sh`) | MIT. The release's `Shaders/` folder holds shaders by other authors with their own licenses; see the notes in each shader file. |
| Debian / Raspberry Pi OS packages (innoextract, unzip, curl) | apt | Each package's license is in `/usr/share/doc/<package>/copyright` on the Pi. |

## Changes to the game folder

The game's executable is not modified. The clean copy stays in `~/ssrw/game.pristine`; in the
working folder:

- `sudtest.ini` gets `VideoMode=2` (800x600).
- cnc-ddraw's `ddraw.dll`, `Shaders/` and this project's `ddraw.ini` go into the game folder; a
  `ddraw.dll` already there is kept as `ddraw.dll.gog`.

If you copy a set-up game home to someone else, you are distributing the game (which you may
not) and cnc-ddraw.

## The game

**Sudden Strike: Resource War** is a commercial game by Fireglow Games, published by Kalypso
Media, and sold by GOG. It is **not** included here and must be bought separately. The setup only
unpacks your own copy of the GOG offline installer. "Sudden Strike" is a trademark of its owner.
This project is not affiliated with or endorsed by them.
