# Changelog — Sudden Strike 2 wrapper

Versions are the wrapper's own (`game.json` → `wrapper.version`). Each entry names the GOG
builds it was tested against.

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
