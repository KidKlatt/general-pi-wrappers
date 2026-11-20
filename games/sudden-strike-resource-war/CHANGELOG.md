# Changelog — Sudden Strike: Resource War wrapper

Versions are the wrapper's own (`game.json` → `wrapper.version`). Each entry names the GOG
build it was tested against.

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
