# general-pi-wrappers

Wrappers that make **GOG games you own** run on a Raspberry Pi through x86 emulation and Wine:
setup scripts, configuration, and sources and patches for open-source DLLs and Mesa.
**No game files are in this repository.** Every wrapper starts from the user's own GOG offline installer and leaves the game's executable unmodified.

The method used to make these (rules, phases, test ladder, templates) lives in the companion
repository [General_Pi_Workshop](https://github.com/KidKlatt/General_Pi_Workshop).

## Games

| Folder | Game | GOG product id(s) | Wrapper | Status |
|---|---|---|---|---|
| [games/medieval-total-war](games/medieval-total-war/) | Medieval: Total War | `1397939414` | 1.3.1 | released ([TWM_Pi](https://github.com/KidKlatt/TWM_Pi)) |
| [games/shogun-total-war](games/shogun-total-war/) | Shogun: Total War – Warlord Edition | `1874325037` | 1.3.1 | playable, Phase 5 (standalone, full screen) |
| [games/sudden-strike-2](games/sudden-strike-2/) | Sudden Strike 2 | `1443986935` | 1.3.0 | playable, Phase 4/5 (widescreen 1280x720) |
| [games/sudden-strike-resource-war](games/sudden-strike-resource-war/) | Sudden Strike: Resource War | `1707288232` | 1.3.0 | playable, Phase 4/5 (split from Sudden Strike 2) |
| [games/civilization-3](games/civilization-3/) | Sid Meier's Civilization III Complete | `1471405734` | 0.12.0 | playable (setup.sh, widescreen) |

The machine-readable version of this table is [catalog.json](catalog.json), generated from each
game's `game.json` by `python tools/build-catalog.py` (run `--check` before merging).

## Layout

```
catalog.json                 what general-pi-manager reads (generated; see "Catalog")
schema/game.schema.json      what a game.json holds
tools/build-catalog.py       builds / checks catalog.json
LICENSE                      MIT, for this repository's own files
games/<slug>/
  game.json                  GOG product ids, installer builds + SHA-256, wrapper version, stack, dependencies
  CHANGELOG.md               wrapper versions, each tied to the GOG build it was tested on
  README.md                  what it does, status, how to set it up
  THIRD-PARTY-NOTICES.md     what the setup downloads, builds and changes, and under which licenses
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

### Config file names

`play.sh` loads three env files from `config/`, in this order. Their names follow one pattern, so
people and general-pi-manager can tell what each one is from its name:

| File | What it holds |
|---|---|
| `pi4-<short_id>.env` | Device and game settings (`GAME_DIR`, `GAME_EXE`, resolution). If the shipped setup runs a different game copy than the workshop's clean one, add a variant: `pi4-<short_id>-<variant>.env` (e.g. `pi4-mtw-lazy.env`), so it never overwrites the development home's own device file |
| `track-<stack>.env` | The emulation stack: `track-hangover.env`, `track-box64.env` |
| `profile-play.env` | The knobs the default `play.sh` (and the main shortcut) runs with |
| `profile-<option>.env` | The knobs for a `play.sh` option, named after it: `--window` loads `profile-window.env` |

A game that needs no extra knobs may ship no profile. Numbered experiment profiles
(`profile-42-…`) belong only in the workshop record; a shipped profile's header comment says
which experiment it came from. When a file is renamed, `setup.sh` removes the old name from an
updated game home (but never from a development home, recognised by
`config/profile-00-baseline.env`).

## Setup interface

Every game whose `game.json` has `"entry_points": {"setup_interface": 1, ...}` follows this, so a
tool (or a person) can set up any game the same way. `build-catalog.py --check` checks the parts
it can, and `catalog.json` carries `setup_interface` per game. All games in this repository
follow it.

**`scripts/pi/setup.sh`**, run on the Pi as the normal user (sudo only for apt):

| Option | Meaning |
|---|---|
| `--installer DIR` | Folder with the GOG installer files listed in `game.json` `files[]`. Needed until the game is unpacked. A build other than the tested one gives a warning, not a stop. |
| `--home DIR` | Game home (default `~/<short_id>`; `<ID>_HOME` in the environment does the same). Everything the game needs lives here. |
| `--allow-upgrades` | Continue even if apt would upgrade or remove installed packages (default: stop). |
| `--no-desktop` | Do not install the shortcuts. |
| `--jobs N` | Parallel build jobs (default 3). Accepted, and ignored, by games that build nothing. |
| `--check` | Only the checks (device, OS, page size, disk, installer present and its checksum, apt simulation). Changes nothing; exits 0 with `READY:` or 3 with `NEEDS YOU:`. |
| `-h`, `--help` | Usage. |

A game may add its own options; it lists them in `entry_points.setup_options` (for example
Medieval's `--private-wine`).

- **Exit codes:** 0 done; 1 failed (run the same command again: finished steps are skipped);
  2 usage error; 3 needs you: something only the user can fix (reboot for 4 KB pages, free disk,
  wrong or missing installer, apt would change packages), printed as `NEEDS YOU: ...`.
- **Progress:** one line per step, `==> [n/N] what it does`; the last line is `==> Done`. A log is
  written to `<home>/logs/setup-<time>.log`.
- **Resume:** each finished step leaves `<home>/.setup/<step>.done`; delete one to redo the step.
- **Result:** on success `<home>/.setup/installed.json` holds `slug`, `short_id`,
  `wrapper_version`, `home`, `installer` (file name), `installer_tested` (`yes`/`no`/`unknown`)
  and `installed` (time). `game.json` is copied into the game home.
- **Shortcuts:** the `.desktop` files in `config/desktop/` use `@GAME_HOME@` in `Exec=` and
  `Icon=`; setup replaces it and installs them into `~/.local/share/applications` and, if it
  exists, `~/Desktop`.
- Nothing outside the game home changes except apt packages and the shortcuts.
- **apt:** only packages that are missing are installed (simulated first); an installed package
  is never upgraded or removed unless the user adds `--allow-upgrades`.
- **sudo:** every sudo call goes through `sudo_`, which runs `sudo -A` when `SUDO_ASKPASS` is set
  (a tool such as general-pi-manager then shows its own password box; the password goes from
  that helper straight to sudo) and plain `sudo` otherwise (a terminal asks as usual).
- **Existing installs are kept:** a game folder, Wine prefix or built component already in the
  game home (for example from a setup by hand, before step markers existed) is kept, never
  unpacked or built again, so a second run or an update keeps saves and settings.

**`scripts/pi/play.sh`** starts the game; no options means full screen. It finds the game home
from its own location (or `<ID>_HOME`), so a game set up with `--home` starts from its shortcut.

| Option | Meaning |
|---|---|
| `--fps` | Frame-rate counter (where the game supports it). |
| `--window` | In a window instead of full screen (where the game supports it). |

Other options are listed in `entry_points.play_options`. Exit codes: 0 played; 1 this game is
already running (it never refuses because a different game runs); 2 not set up, or usage error.

**`scripts/pi/uninstall.sh`** removes the game: its game home (the game with its saves and
settings, the Wine prefix, everything the setup built there) and the shortcuts the setup
installed. It is announced in `entry_points.uninstall`; a game without one shows a disabled
Remove button in the manager ("remove it by hand"). The file is the same for every game (copy it
from any game folder): it reads what to remove from the game home's `game.json`.

| Option | Meaning |
|---|---|
| `--home DIR` | Game home to remove (default: the home the script is in). |
| `--yes` | Do not ask (for a tool that already asked the user). Without it, it asks in a terminal and stops with exit 3 when there is none. |
| `--check` | Only list what would be removed. |

Exit codes: 0 removed (or listed); 1 failed; 2 usage error; 3 needs you (the game is running, no
confirmation, or the folder is not a game home with `game.json`, `config/` and `scripts/pi/`).
It never removes apt packages, because other games and programs may use them; each game's README
names the packages its setup installs.

## Catalog

`catalog.json` (`catalog_version` 2) is what general-pi-manager reads: one entry per game with
`slug`, `short_id`, `title`, `path`, `wrapper_version`, `tag`, `status`, `min_manager_version`,
`setup_interface`, `uninstall`, `summary`, `known_issues` (a count), `requirements`,
`performance` (per measured target: device, RAM, config, typical and low FPS, rating) and
`products` (GOG ids and the tested installer files with size and SHA-256). It is generated from
each `game.json`; never edit it by hand.

- `tag` is `<slug>/v<version>`, made when that version is merged to `main` (Versioning, below).
  The manager downloads the game folder at that tag.
- FPS in `targets[].fps` are the recorded measurements: `typical` is the average in the main
  scene, or the lower end where only a range was recorded; `low` is the minimum. Nothing is
  estimated; unknown values are `null`.
- `rating` (`smooth`, `playable`, `rough`, `broken`) is set by a person who played that setup;
  it stays `null` until then.
- `min_manager_version` rises when the catalog changes in a way older managers cannot read.

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

## Third-party notices

Every game folder has a `THIRD-PARTY-NOTICES.md` (`build-catalog.py --check` fails without one).
It lists, for that game:

- what the setup downloads or installs (source, pinned version, license),
- files in the folder that are not covered by the MIT license (patches against Wine or Mesa, and
  scripts that carry excerpts of their source),
- what is built on the Pi from those sources,
- tools the user has to get themselves, which are never shipped or downloaded (such as Sudden
  Strike 2's widescreen patcher),
- every change the setup makes to the unpacked game folder,
- the game, its owners, and that it is not included.

Update it in the same change whenever a download, a build step, a patch or a change to the game
folder is added or removed.

## License

This repository's own files (scripts, configuration, docs, shim source) are under the
[MIT license](LICENSE). Patches against Wine and Mesa, and the scripts that apply them with
excerpts of the Wine source, fall under those projects' licenses (LGPL 2.1+ and mainly MIT).
Emulators, Wine, Mesa and helper tools are downloaded from their official releases during setup,
not stored here. Each game's `THIRD-PARTY-NOTICES.md` has the details. The games are commercial
and not included.
