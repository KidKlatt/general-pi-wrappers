# general-pi-wrappers

Wrappers that make **GOG games you own** run on a Raspberry Pi through x86 emulation and Wine:
setup scripts, configuration, and sources and patches for open-source DLLs and Mesa.
**No game files are in this repository.** Every wrapper starts from the user's own GOG offline installer and leaves the game's executable unmodified.

The method used to make these (rules, phases, test ladder, templates) lives in the companion
repository [General_Pi_Workshop](https://github.com/KidKlatt/General_Pi_Workshop).

## Games

| Folder | Game | GOG product id(s) | Wrapper | Status |
|---|---|---|---|---|
| [games/medieval-total-war](games/medieval-total-war/) | Medieval: Total War | `1397939414` | 1.0.0 | released ([TWM_Pi](https://github.com/KidKlatt/TWM_Pi)) |
| [games/shogun-total-war](games/shogun-total-war/) | Shogun: Total War – Warlord Edition | `1874325037` | 1.0.0 | playable, Phase 5 (standalone, full screen) |
| [games/sudden-strike-2](games/sudden-strike-2/) | Sudden Strike 2 + Sudden Strike: Resource War | `1443986935`, `1707288232` | 0.9.0 | playable, Phase 4/5 |

The machine-readable version of this table is [catalog.json](catalog.json), generated from each
game's `game.json` by `python tools/build-catalog.py` (run `--check` before merging).

## Layout

```
catalog.json                 index: GOG product id -> wrapper folder (generated)
schema/game.schema.json      what a game.json holds
tools/build-catalog.py       builds / checks catalog.json
LICENSE                      MIT, for this repository's own files
games/<slug>/
  game.json                  GOG product ids, installer builds + SHA-256, wrapper version, stack, dependencies
  CHANGELOG.md               wrapper versions, each tied to the GOG build it was tested on
  README.md                  what it does, status, how to set it up
  config/ scripts/pi/        what the Pi needs to install and run it
  tools/ patches/            own shims and patches against Wine / Mesa (source only; built on the Pi)
  docs/                      setup guides
```

Only what a user's Pi needs is here. The working record of each game (STATE, EXPERIMENTS,
research scripts, probes, test runs) is in the workshop repository under `projects/<slug>/`.

Each game folder is self-contained: copy it to a Pi and its scripts work from there. Code shared
by two games (for example the d3d9lazy shim used by Medieval and Shogun) is still copied into
each game, because each game carries its own variant; promote it to a shared folder only once
two games use the identical file.

## Versioning

- **Wrapper version** (`game.json` → `wrapper.version`, semver). Bump it on each merge to `main`
  that changes behaviour, and add a `CHANGELOG.md` entry naming the GOG build it was tested on.
  Tag merges as `<slug>/v<version>`.
- **GOG package** (`game.json` → `gog_products[]`): `product_id` (GOG `gameId`), `gog_build_id`
  (from `goggame-<id>.info`), `gog_installer_build` (the number in the installer file name) and
  the installer files' sizes and SHA-256. When GOG ships a new installer, record it as a new
  tested build before claiming the wrapper supports it.
- `depends_on` / `provides` list things on the Pi that one game's setup installs and another
  uses (none at the moment; Shogun builds its own Box64 and Mesa since 1.0.0).

## Branches

`main` holds wrappers that work. A new game, or a large change to one, is developed on a
branch `game/<slug>` and merged back when it is ready; see the workshop's
[WORKFLOW.md](https://github.com/KidKlatt/General_Pi_Workshop/blob/main/WORKFLOW.md).

## License

This repository's own files (scripts, configuration, docs, shim source, patch scripts) are under
the [MIT license](LICENSE). Patches against Wine and Mesa fall under those projects' licenses
(LGPL 2.1+ and mainly MIT). Emulators, Wine, Mesa and helper tools are downloaded from their
official releases during setup, not stored here. See each game's README and
[games/medieval-total-war/THIRD-PARTY-NOTICES.md](games/medieval-total-war/THIRD-PARTY-NOTICES.md).
The games are commercial and not included.
