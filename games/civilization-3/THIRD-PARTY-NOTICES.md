# Third-party software and content

The MIT license in [LICENSE](../../LICENSE) covers only this project's own work: the scripts, the
configuration files (including `config/game/conquests.ini`) and the documentation.

This project mostly glues together other people's work, and that work keeps its own license.
**Check the license of each project below yourself before you reuse, modify or redistribute
anything.** The summaries here are a pointer, not legal advice, and licenses can change between
versions.

## Downloaded or installed by the setup script (not stored in this repo)

| Component | Where it comes from | License (check the source) |
|---|---|---|
| Hangover 11.16 (`hangover-wine`, `hangover-wowbox64`) | https://github.com/AndreRH/hangover (official release, SHA-256 checked), installed with apt if missing | Hangover and its Wine are LGPL 2.1 or later; the WowBox64 back-end comes from Box64, which is MIT. See the Hangover repository. |
| Debian / Raspberry Pi OS packages (innoextract, wlr-randr) | apt | Each package's license is in `/usr/share/doc/<package>/copyright` on the Pi. |

Nothing is built on the Pi, and this repo stores no patches or third-party code.

## Changes to the game folder

The game's executables are not modified. In the unpacked game:

- GOG's own `__support/save` files (from your installer: a font and Conquests rules files) are
  copied into the game where missing, as GOG's installer does on Windows.
- `Conquests/conquests.ini` gets `KeepRes=1` and `PlayIntro=0`.
- The Wine prefix gets the registry keys the game looks for (`Install_Path`).

While playing, `play.sh` switches the display mode with `wlr-randr` and switches it back after.

If you copy a set-up game home to someone else, you are distributing the game, which you may not.

## The game

**Sid Meier's Civilization III Complete** is a commercial game by Firaxis Games, first published
by Infogrames and now 2K, and sold by GOG. It is **not** included here and must be bought
separately. The setup only unpacks your own copy of the GOG offline installer. "Sid Meier's
Civilization" and "Civilization" are trademarks of their owners. This project is not affiliated
with or endorsed by them.
