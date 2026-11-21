# Changelog — Sudden Strike: Resource War wrapper

Versions are the wrapper's own (`game.json` → `wrapper.version`). Each entry names the GOG
build it was tested against.

## 1.2.0 — 2026-11-21

No change to the tested setup.

- **New: `scripts/pi/uninstall.sh`** (setup interface, general-pi-wrappers README): removes the
  game home (game, saves, settings, Wine prefix) and the shortcuts after a confirmation
  (`--yes` skips it, `--check` only lists); never removes apt packages; refuses while the game
  runs or when the folder is not this game's home.
- `game.json`: structured `targets` (FPS as numbers, what was tested), `notes` (summary, known
  issues, tips) and `requirements`, read by the catalog.

## 1.1.0 — 2026-11-20

Tested against GOG product `1707288232` (Sudden Strike: Resource War, installer build `13581`). The setup reproduces
the tested setup; the script itself has not yet run on a clean Pi.

- **New: `scripts/pi/setup.sh`** (standard setup interface, general-pi-wrappers README,
  "Setup interface"): installs `innoextract`, `unzip`, `curl` and Hangover 11.16 with
  `hangover-libwow64fex` if missing, extracts the installer (with a hard-linked clean copy `game.pristine`), sets `VideoMode=2`,
  installs cnc-ddraw, creates the
  Wine prefix and adds the shortcut. Options `--installer --home --allow-upgrades --no-desktop
  --jobs --check`; exit codes 0/1/2/3. A game folder or prefix already there is kept.
- No longer depends on another game's setup for Hangover or FEX.
- `play.sh` finds the game home from its own location and the config follows the home;
  the shortcut uses `@GAME_HOME@`, filled in by the setup.

## 1.0.1 — 2026-11-20

Tested against GOG product `1707288232` (Sudden Strike: Resource War, installer build `13581`).
No change to the tested setup.

- `play.sh` no longer refuses to start while another game's Wine runs (it exited with code 3);
  it only refuses a second copy of Resource War, told apart from Sudden Strike 2 by its Wine
  prefix. `scripts/pi/busy-check.sh` is removed (a development-only check).

## 1.0.0 — 2026-11-20

Tested against GOG product `1707288232` (Sudden Strike: Resource War, installer build `13581`).

- Split off from `games/sudden-strike-2` 0.9.0, where this game was set up together with Sudden
  Strike 2 (same engine). Own Pi folder `~/ssrw`, own Wine prefix, own desktop shortcut.
- Hangover 11.16 with the FEX back-end (WowBox64 hangs on saving), cnc-ddraw 7.1.0.0 stretched
  full screen (downloaded and SHA-256 checked by `install-cnc-ddraw.sh`).
- `play.sh [--fps] [--fit|--window]`; refuses to start while another game's Wine runs
  (`busy-check.sh`, exit 3).
- Tested after the move with a fresh prefix: 57.5 avg / 50.6 min FPS in the first single mission;
  save (F11) and load (F12) work, saves made under 0.9.0 load.
