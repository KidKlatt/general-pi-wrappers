# Changelog — Sudden Strike 2 wrapper

Versions are the wrapper's own (`game.json` → `wrapper.version`). Each entry names the GOG
builds it was tested against.

## 1.1.0 — 2026-11-20

Tested against GOG product `1443986935` (Sudden Strike 2, installer build `13718`). The setup reproduces
the tested setup; the script itself has not yet run on a clean Pi.

- **New: `scripts/pi/setup.sh`** (standard setup interface, general-pi-wrappers README,
  "Setup interface"): installs `innoextract`, `unzip`, `curl` and Hangover 11.16 with
  `hangover-libwow64fex` if missing, extracts the installer (with a hard-linked clean copy `game-ss2.pristine`), applies GOG's
  `winmm_override` music files, sets `VideoMode=2`, installs cnc-ddraw, creates the
  Wine prefix and adds the shortcut. Options `--installer --home --allow-upgrades --no-desktop
  --jobs --check`; exit codes 0/1/2/3. A game folder or prefix already there is kept.
- No longer depends on another game's setup for Hangover or FEX.
- `play.sh` finds the game home from its own location and the config follows the home;
  the shortcut uses `@GAME_HOME@`, filled in by the setup.

## 1.0.1 — 2026-11-20

Tested against GOG product `1443986935` (Sudden Strike 2, installer build `13718`). No change to
the tested setup.

- `play.sh` no longer refuses to start while another game's Wine runs (it exited with code 3);
  it only refuses a second copy of Sudden Strike 2, told apart from Resource War by its Wine
  prefix. `scripts/pi/busy-check.sh` is removed (a development-only check).

## 1.0.0 — 2026-11-20

Tested against GOG product `1443986935` (Sudden Strike 2, installer build `13718`).

- **Resource War moved out** to its own wrapper, `games/sudden-strike-resource-war` (its own
  folder `~/ssrw`, prefix and shortcut). Users of 0.9.0 move it as that README describes; this is
  why the major version changes.
- `play.sh` takes no game argument any more (`play.sh ss2` still works; `play.sh rw` prints where
  the game went). It refuses to start while another game's Wine runs (`busy-check.sh`, exit 3).
- `install-cnc-ddraw.sh` downloads the cnc-ddraw 7.1.0.0 release itself and checks its SHA-256.
- Re-tested after the split: 59.7 avg / 51.7 min FPS in the first single mission at 1280x720.

## 0.9.0 — 2026-11-17

Tested against GOG products `1443986935` (Sudden Strike 2, installer build `13718`) and
`1707288232` (Resource War, installer build `13581`).

- Imported into general-pi-wrappers from the working folder `Pi_SS2` (experiments 1–24).
- Hangover 11.16 with the FEX back-end (WowBox64 hangs on saving), cnc-ddraw 7.1.0.0 stretched
  full screen, Sudden Strike 2 widescreen 1280x720 via the sandboxed community patcher.
- `play.sh ss2|rw` and desktop shortcuts. No setup script for a new Pi yet.
