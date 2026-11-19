# Changelog — Medieval: Total War wrapper

Versions are the wrapper's own (`game.json` → `wrapper.version`). Each entry names the GOG
build it was tested against.

## 1.0.0 — 2026-11-16

Tested against GOG product `1397939414`, offline installer build `86311` (gog_build_id `59131712679784536`).

- Imported into general-pi-wrappers on 2026-11-18: the same files as the public
  https://github.com/KidKlatt/TWM_Pi at commit `9122d81`. The working record (STATE,
  EXPERIMENTS 1–141, research scripts, shim versions v1–v11) is in General_Pi_Workshop.
- Hangover 11.16 / WowBox64, d3d9lazy shim v10, patched Mesa 26.2.6, `VideoMemorySize=512`.
- `scripts/pi/setup-new-pi.sh` reproduces the setup on a new Pi (`--private-wine` option).
