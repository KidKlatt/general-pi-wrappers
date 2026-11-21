# Changelog — Medieval: Total War wrapper

Versions are the wrapper's own (`game.json` → `wrapper.version`). Each entry names the GOG
build it was tested against.

## 1.1.0 — 2026-11-20

Tested against GOG product `1397939414`, offline installer build `86311`. Not yet run on a Pi in
this version.

- **Standard setup interface** (general-pi-wrappers README, "Setup interface"): the setup is
  `scripts/pi/setup.sh` (`setup-new-pi.sh` forwards to it for now). It accepts `--installer DIR`, `--home DIR`,
  `--allow-upgrades`, `--no-desktop`, `--jobs N` and `--check` (checks only, changes nothing).
  Exit codes: 0 done, 1 failed (rerun to resume), 2 usage error, 3 needs you (the message starts
  with `NEEDS YOU:`). Progress lines read `==> [n/N] step`.
- On success the setup writes `<home>/.setup/installed.json` (slug, wrapper version, installer,
  whether it is the tested build, date) and copies `game.json` into the game home.
- Shortcuts go into the app menu and, if `~/Desktop` exists, onto the desktop; the `.desktop`
  files use `@GAME_HOME@`, which the setup replaces with the game home.
- `play.sh` finds the game home from its own location; the config files follow `MTW_HOME`, so a game set up with
  `--home` starts from its shortcut.

## 1.0.0 — 2026-11-16

Tested against GOG product `1397939414`, offline installer build `86311` (gog_build_id `59131712679784536`).

- Imported into general-pi-wrappers on 2026-11-18: the same files as the public
  https://github.com/KidKlatt/TWM_Pi at commit `9122d81`. The working record (STATE,
  EXPERIMENTS 1–141, research scripts, shim versions v1–v11) is in General_Pi_Workshop.
- Hangover 11.16 / WowBox64, d3d9lazy shim v10, patched Mesa 26.2.6, `VideoMemorySize=512`.
- `scripts/pi/setup-new-pi.sh` reproduces the setup on a new Pi (`--private-wine` option).
