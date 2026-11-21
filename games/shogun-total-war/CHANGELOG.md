# Changelog — Shogun: Total War wrapper

Versions are the wrapper's own (`game.json` → `wrapper.version`). Each entry names the GOG
build it was tested against.

## 1.1.0 — 2026-11-20

Tested against GOG product `1874325037`, offline installer build `86790` (gog_build_id `59191766611906857`).
Not yet run on a Pi in this version.

- **Standard setup interface** (general-pi-wrappers README, "Setup interface"): the setup is
  `scripts/pi/setup.sh` (`setup-new-pi.sh` forwards to it for now). It accepts `--installer DIR`, `--home DIR`,
  `--allow-upgrades`, `--no-desktop`, `--jobs N` and `--check` (checks only, changes nothing).
  Exit codes: 0 done, 1 failed (rerun to resume), 2 usage error, 3 needs you (the message starts
  with `NEEDS YOU:`). Progress lines read `==> [n/N] step`.
- On success the setup writes `<home>/.setup/installed.json` (slug, wrapper version, installer,
  whether it is the tested build, date) and copies `game.json` into the game home.
- Shortcuts go into the app menu and, if `~/Desktop` exists, onto the desktop; the `.desktop`
  files use `@GAME_HOME@`, which the setup replaces with the game home.
- `play.sh` finds the game home from its own location; the config files follow `STW_HOME`, so a game set up with
  `--home` starts from its shortcut.

## 1.0.1 — 2026-11-20

Tested against GOG product `1874325037`, offline installer build `86790` (gog_build_id `59191766611906857`).
No change to the tested setup: the game, its build and its settings are the same as 1.0.0.

- Removed `scripts/pi/guard.sh` and the baseline snapshot step in `setup-new-pi.sh`. It is a
  development tool that protects the development Pi's other services, not something a player needs.
- `play.sh` no longer refuses to start while another game's Wine runs; it only refuses a second
  copy of Shogun. `scripts/pi/busy-check.sh` is removed (a development-only check), and so is
  its use in `setup-new-pi.sh` before the Wine prefix is created.
- `docs/RUNBOOK.md`: notes written for players instead of the development workflow (no
  references to the development Pi's rules or internal notes).

## 1.0.0 — 2026-11-19

Tested against GOG product `1874325037`, offline installer build `86790` (gog_build_id `59191766611906857`).

- **Standalone; redo the setup.** Nothing from Medieval: Total War's setup is used any more.
  `scripts/pi/setup-new-pi.sh` builds Box64 0.4.5 from source (commit `a46caf3`), downloads
  Kron4ek's Wine 9.17, builds `dsound.dll` and `winex11.so` from the Wine 9.17 source and Mesa
  26.2.6 with `patches/mesa-v3d-busy-range.patch`, all into `~/stw` with pinned SHA-256.
- **Full screen** by default: `winex11.so` sets Xwayland emulated modes
  (`tools/winex11/apply-xwayland-modeset.py`); menus (800x600) are stretched, a 16:9 battle
  resolution fills the screen. `config/profile-final-pi4.env`.
- `scripts/pi/play.sh` launcher (`--fps`, `--window`) and two desktop shortcuts.
- Gate 4: three full test runs in a row (menu, custom battle with unit control, 15 minutes of
  battle, new campaign, End Turn, save, quit, load): 35.6–36.6 average / 24.5–27.6 minimum FPS
  while fighting, 0 s below 15, at most 56 °C, no throttling.
- Not yet: sound check on better speakers (Gate 5). The new setup ran once end to end on the
  development Pi; it has not been run on a second, clean Pi.

## 0.9.0 — 2026-11-18

Tested against GOG product `1874325037`, offline installer build `86790` (gog_build_id `59191766611906857`).

- Imported into general-pi-wrappers from the working folder `Pi_TW_Shogun` (experiments 1–56).
- Track B: Box64 0.4.5 + private Wine 9.17 WoW64 with patched `winex11.so` (campaign-start
  deadlock fix), d3d9lazy shim with a per-frame draw gate, linear-resampler `dsound.dll`,
  patched `ddraw.dll` (no3d), MTW's patched Mesa.
- Not yet: own Box64 copy, `play.sh`, desktop shortcut, setup script (Phase 5).
