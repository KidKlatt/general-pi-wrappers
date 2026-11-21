# Changelog — Civilization III Complete wrapper

Versions are the wrapper's own (`game.json` → `wrapper.version`). Each entry names the GOG
build it was tested against.

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
