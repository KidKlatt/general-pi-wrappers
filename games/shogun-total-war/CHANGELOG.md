# Changelog — Shogun: Total War wrapper

Versions are the wrapper's own (`game.json` → `wrapper.version`). Each entry names the GOG
build it was tested against.

## 0.9.0 — 2026-11-18

Tested against GOG product `1874325037`, offline installer build `86790` (gog_build_id `59191766611906857`).

- Imported into general-pi-wrappers from the working folder `Pi_TW_Shogun` (experiments 1–56).
- Track B: Box64 0.4.5 + private Wine 9.17 WoW64 with patched `winex11.so` (campaign-start
  deadlock fix), d3d9lazy shim with a per-frame draw gate, linear-resampler `dsound.dll`,
  patched `ddraw.dll` (no3d), MTW's patched Mesa.
- Not yet: own Box64 copy, `play.sh`, desktop shortcut, setup script (Phase 5).
