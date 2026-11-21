# Sid Meier's Civilization III Complete on a Raspberry Pi

Runs the GOG release of **Sid Meier's Civilization III Complete** (product `1471405734`, all
three games through Conquests 1.22) on a Raspberry Pi through Hangover 11.16 with its WowBox64
x86 emulator and Wine's Wayland driver, in **widescreen**. **You need your own copy of the game**
(GOG offline installer); nothing from the game is in this repository and no game file is
modified.

Measured on a Pi 4 (4 GB) at 1440x810: map scrolling about 18-20 FPS early in a game and 13-15
FPS in a large late game (about 7 % more with a 2.0 GHz overclock); the idle map animates at
the game's own 15 FPS. Tested: main menu areas, Quick Start, a custom game (Large, Pangaea),
several turns (about 4 s per early turn), saving and loading, a large late-game save. A Pi 5
should be noticeably smoother (not tested yet).

## Setup

Needs Raspberry Pi OS 64-bit based on Debian 13 "trixie" with the default desktop (labwc,
Wayland), about 5 GB free, and your GOG offline installer
`setup_civilization3_complete_2.0.0.7.exe` (from your GOG library, "Download offline backup game
installers").

```bash
git clone https://github.com/KidKlatt/general-pi-wrappers
general-pi-wrappers/games/civilization-3/scripts/pi/setup.sh --installer ~/Downloads
```

`setup.sh` installs `innoextract` and `wlr-randr` if missing, and Hangover 11.16 from its
official release if it is not installed (apt is simulated first; it stops if any installed package
would be upgraded or removed, unless you add `--allow-upgrades`). It then sets the game up in
`~/civ3` (`--home DIR` for another place): extracts the installer, places the files GOG's own
installer adds, writes `conquests.ini`, creates the Wine prefix with the game's registry keys and
adds a **Civilization III** desktop shortcut. A second run resumes where it stopped. sudo is used
only for apt.

On a Pi 5, Hangover needs the 4 KB-page kernel: add `kernel=kernel8.img` to
`/boot/firmware/config.txt` and reboot first (setup.sh checks this).

## Playing

Start it with the desktop shortcut or `~/civ3/scripts/pi/play.sh`. While the game runs, the
HDMI output switches to **1440x810** if your display offers it (otherwise the first of 1600x900,
1366x768, 1440x900, 1280x800, 1680x1050, 1920x1080, 1280x1024, 1024x768 that it offers; the game
quits without a mode of at least 1024x768) and switches back when you quit. Choose the mode
yourself with `CIV3_MODE=1600x900 ~/civ3/scripts/pi/play.sh`. Smaller modes are faster.

- `play.sh --x11`: run through Xwayland instead of the Wayland driver (less than half the speed; only
  useful if the Wayland path gives you trouble).
- Logs: `~/civ3/logs/play-*.log`.

| File | Purpose |
|---|---|
| `scripts/pi/setup.sh` | One-time setup (see above) |
| `scripts/pi/play.sh [--x11]` | Starts the game; used by the shortcut |
| `scripts/pi/with-mode.sh` | Switches the display mode for one command and always restores it |
| `config/track-hangover.env` | Hangover paths, the game's own prefix `~/civ3/prefixes/hangover` |
| `config/pi4-civ3.env` | Game folder and executable |
| `config/game/conquests.ini` | `KeepRes=1` (widescreen), `PlayIntro=0` (skips the intro video) |
| `config/desktop/Civilization-III.desktop` | Shortcut template (setup.sh writes the real path) |

## How it works, briefly

- The game is started from `Conquests/` (from the game root it loads the wrong files and crashes)
  and needs GOG's `Install_Path` registry keys, which setup.sh writes into its own prefix.
- **Wine's Wayland driver** (`DISPLAY` unset) is about twice as fast as X11 here: under Xwayland
  the game's OpenGL child window is composited on the CPU.
- **WowBox64** with `BOX64_DYNAREC_CALLRET=1` beats the FEX back-end for this game; saving works
  with it (unlike Sudden Strike 2).
- The intro video switches to 640x480, which breaks the window under the Wayland driver, so
  `PlayIntro=0` must be in the `[Conquests]` section of `conquests.ini`.
- The main thread is CPU-bound (the map is drawn in software, the GPU is about 1 % busy), so a
  CPU overclock helps a little and a GPU overclock does not. Replacing the hottest drawing loop
  with native ARM code was tried and gave nothing measurable: Box64 already runs it near native
  speed.

The full record (97 experiments) is in
[General_Pi_Workshop/projects/civilization-3](https://github.com/KidKlatt/General_Pi_Workshop/tree/main/projects/civilization-3).

## License

The scripts, configuration and docs here are MIT ([LICENSE](../../LICENSE)). Hangover/Wine
(LGPL 2.1+) and Box64 (MIT) keep their own licenses and are installed from their official
release, not stored here. Civilization III is a commercial game and is not included.
