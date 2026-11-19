# Changelog — Sudden Strike 2 / Resource War wrapper

Versions are the wrapper's own (`game.json` → `wrapper.version`). Each entry names the GOG
builds it was tested against.

## 0.9.0 — 2026-11-17

Tested against GOG products `1443986935` (Sudden Strike 2, installer build `13718`) and
`1707288232` (Resource War, installer build `13581`).

- Imported into general-pi-wrappers from the working folder `Pi_SS2` (experiments 1–24).
- Hangover 11.16 with the FEX back-end (WowBox64 hangs on saving), cnc-ddraw 7.1.0.0 stretched
  full screen, Sudden Strike 2 widescreen 1280x720 via the sandboxed community patcher.
- `play.sh ss2|rw` and desktop shortcuts. No setup script for a new Pi yet.
