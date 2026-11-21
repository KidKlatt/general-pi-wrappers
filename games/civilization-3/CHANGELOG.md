# Changelog — Civilization III Complete wrapper

Versions are the wrapper's own (`game.json` → `wrapper.version`). Each entry names the GOG
build it was tested against.

## 0.12.0 — 2026-11-21

No change to the tested setup. `setup.sh --check` passes against the existing
game home on the development Pi.

- `sudo` runs through `sudo_`: with `SUDO_ASKPASS` set (general-pi-manager's password box) it
  uses `sudo -A`; in a terminal nothing changes.
- A game folder or Wine prefix already in the game home (set up before step markers existed) is
  kept instead of unpacked again, so saves stay; no installer is needed then.

## 0.11.0 — 2026-11-21

No change to the tested setup.

- **New: `scripts/pi/uninstall.sh`** (setup interface, general-pi-wrappers README): removes the
  game home (game, saves, settings, Wine prefix) and the shortcuts after a confirmation
  (`--yes` skips it, `--check` only lists); never removes apt packages; refuses while the game
  runs or when the folder is not this game's home.
- `game.json`: structured `targets` (FPS as numbers, what was tested), `notes` (summary, known
  issues, tips) and `requirements`, read by the catalog.

## 0.10.0 — 2026-11-20

Tested against GOG product `1471405734`, offline installer `setup_civilization3_complete_2.0.0.7.exe`
(GOG version 2.0.0.7, SHA-256 `4ad54ca3…2395`). Not yet run on a Pi in this version.

- **Standard setup interface** (general-pi-wrappers README, "Setup interface"): the setup is
  `scripts/pi/setup.sh`. It accepts `--installer DIR`, `--home DIR`,
  `--allow-upgrades`, `--no-desktop`, `--jobs N` and `--check` (checks only, changes nothing).
  Exit codes: 0 done, 1 failed (rerun to resume), 2 usage error, 3 needs you (the message starts
  with `NEEDS YOU:`). Progress lines read `==> [n/N] step`.
- On success the setup writes `<home>/.setup/installed.json` (slug, wrapper version, installer,
  whether it is the tested build, date) and copies `game.json` into the game home.
- Shortcuts go into the app menu and, if `~/Desktop` exists, onto the desktop; the `.desktop`
  files use `@GAME_HOME@`, which the setup replaces with the game home.
- `play.sh` finds the game home from its own location, so a game set up with
  `--home` starts from its shortcut.

## 0.9.1 — 2026-11-20

Tested against GOG product `1471405734`, offline installer `setup_civilization3_complete_2.0.0.7.exe`
(GOG version 2.0.0.7, SHA-256 `4ad54ca3…2395`). No change to the tested setup.

- `play.sh` no longer refuses to start while another game's Wine runs; it only refuses a second
  copy of Civilization III. `scripts/pi/busy-check.sh` is removed (a development-only check).

## 0.9.0 — 2026-11-20

Tested against GOG product `1471405734`, offline installer `setup_civilization3_complete_2.0.0.7.exe`
(GOG version 2.0.0.7, SHA-256 `4ad54ca3…2395`).

- First release. Hangover 11.16 with WowBox64 (`BOX64_DYNAREC_CALLRET=1`), Wine's Wayland driver,
  widescreen through `KeepRes=1` and a temporary display mode (1440x810 preferred).
- `setup.sh` for a new Pi; tested from a clean folder and prefix on the Pi 4 it was made on, where
  Hangover was already installed (the Hangover-install branch is not yet tested on a fresh Pi).
- `play.sh` and the desktop shortcut.
