# Setting up Medieval: Total War on a new Raspberry Pi

This repeats the working Pi 4 setup on another Pi with one script,
[`scripts/pi/setup-new-pi.sh`](../scripts/pi/setup-new-pi.sh). The result is the same as the
working Pi: Hangover 11.16 (Wine with the WowBox64 x86 emulator), the project's d3d9lazy shim,
a private patched Mesa driver, and the full-screen launcher `play.sh` with desktop shortcuts.

Budget about 45 minutes on a Pi 4, most of it the Mesa build.

## What you need

| | |
|---|---|
| Pi | Raspberry Pi 4 (tested, 4 GB). A Pi 5 should work but has never been tried; see [Pi 5](#pi-5). |
| OS | 64-bit Raspberry Pi OS (or Debian) **13 "trixie"** with the normal desktop. Hangover's package is built for trixie; the script refuses anything else. |
| Display | A monitor on HDMI and the desktop logged in. The game runs in the desktop session (labwc/Wayland with Xwayland, the Raspberry Pi OS default). |
| Disk | 10 GB free in your home folder. |
| Network | Internet on the Pi: the script downloads Hangover from its GitHub release page and Mesa from archive.mesa3d.org, and checks both against pinned SHA-256 sums. |
| Game | Your own copy of Medieval: Total War from GOG, as the **offline backup installer**: **two files**, an `.exe` and a `.bin` (about 1.6 GB together). See [step 2](#2-put-the-gog-installer-on-the-pi). |
| Account | A normal user with sudo (asked once, for apt). Any user name works. |
| Other Wine | **Read [Already using Wine?](#already-using-wine) first** if this Pi runs other Windows programs. |

## Already using Wine?

By default the script installs Hangover's Wine as **the system Wine** (`/usr/bin/wine`). Its
package declares a conflict with Debian's `wine` packages, so it would replace them. What that
means for you:

| What you have now | What happens |
|---|---|
| No Wine | Nothing to worry about. |
| Wine from a tarball, e.g. Pi-Apps' "Wine (x86)" with Box86/Box64 (`wine` in `/usr/local/bin` or `~/wine`) | No clash. Your `wine` command and `~/.wine` stay as they are; the game calls Hangover by its full path and uses its own prefix in `~/mtw/prefixes`. (Hangover and Box64/Box86 Wine builds ran side by side on the development Pi.) |
| A Wine **package** from apt (`wine`, `wine64`, `winehq-*`, …) or some other `/usr/bin/wine` | The script **stops before installing anything** and says so. Rerun with `--private-wine`. |

`--private-wine` unpacks Hangover into `~/mtw/hangover` instead of installing it. Only the
libraries it needs come from apt. Your Wine stays the system Wine, and only the game uses the
private copy:

```bash
bash ~/pi-total-war/scripts/pi/setup-new-pi.sh --installer ~/gog --private-wine
```

This was tested on a Pi 4: the script ran through, and the game started to its menu in full
screen with every Wine file loaded from `~/mtw/hangover`.

If you would rather make Hangover your system Wine, remove your Wine package yourself first and
run the script without the option. Hangover also runs x86 Windows programs, but your other
programs have not been tested with it.

## Steps

### 1. Get the project onto the Pi

In a terminal on the Pi:

```bash
git clone https://github.com/KidKlatt/TWM_Pi ~/pi-total-war
```

### 2. Put the GOG installer on the Pi

The game is not in this repo; you need your own copy from GOG.

1. Sign in at gog.com, open Medieval: Total War in your game library, and download the
   **offline backup installer** for Windows (not the GOG Galaxy installer).
2. It is **two files**, and the setup needs **both**:
   - `setup_medieval_total_war_….exe`
   - `setup_medieval_total_war_…-1.bin`

   The tested version is `setup_medieval_total_war_gog_v1_(86311)`. A newer GOG build will
   probably work too; the script warns but carries on.
3. Put both files in a folder called `gog` in your home folder on the Pi (`/home/<you>/gog`).

The easiest way is to download them on the Pi itself with its web browser; they land in
`~/Downloads`. Then move them:

```bash
mkdir -p ~/gog
```

```bash
mv ~/Downloads/setup_medieval_total_war* ~/gog/
```

Downloaded them on another computer instead? Copy both files onto a USB stick, plug it into the
Pi, and drag them into `~/gog` with the file manager. Any other folder works too, as long as both
files are in the same one: give that folder to the script with `--installer` in the next step.

### 3. Run the setup script

On the Pi (over SSH or in a terminal on its desktop). Use tmux so an SSH drop does not stop it:

```bash
tmux new -s setup
```

```bash
bash ~/pi-total-war/scripts/pi/setup-new-pi.sh --installer ~/gog
```

If the SSH session drops, log in again and reattach with `tmux attach -t setup`.

What it does, in order (each step is skipped on a rerun once it has finished):

1. **Checks** the Pi: 64-bit, trixie, 4 KB kernel pages, free space, sudo.
2. **Copies** `scripts`, `config`, `tools`, `patches` into `~/mtw`, where everything lives.
3. **apt packages**: innoextract, xdotool, grim, tmux, the mingw cross-compiler for the shim,
   and the Mesa build dependencies. It simulates the install first and **stops without
   installing anything if apt would upgrade or remove an existing package** (this protects a Pi
   that also runs a server). If you have checked the list and it is fine, rerun with
   `--allow-upgrades`.
4. **Hangover 11.16**: downloads the official Debian 13 release, checks its SHA-256, installs
   `hangover-wine`, `hangover-wowbox64`, `hangover-libarm64ecfex` (with `--private-wine`:
   unpacks them into `~/mtw/hangover` instead).
5. **Game**: unpacks the installer natively with innoextract into `~/mtw/game-lazy` (no
   emulation, no Windows installer run). It warns if the installer is a different GOG build.
6. **d3d9lazy shim**: compiles `tools/d3d9lazy/d3d9lazy.c` into `~/mtw/game-lazy/d3d9.dll`.
7. **Patched Mesa 26.2.6**: downloads, checks, applies `patches/mesa-v3d-busy-range.patch` to
   the V3D driver and builds it into `~/mtw/mesa-patched`. Only the game uses it; the system Mesa
   is not touched. About 20 minutes on a Pi 4.
8. **Wine prefix** in `~/mtw/prefixes/hangover` (a few minutes; Mono/RPC messages are normal).
9. **Shortcuts** "Medieval Total War" and "Medieval Total War (FPS counter)" on the desktop
   (if `~/Desktop` exists) and in the app menu.

The full log is in `~/mtw/logs/setup-<date>.log`.

### 4. Play

Double-click **Medieval Total War** on the desktop, or run:

```bash
~/mtw/scripts/pi/play.sh
```

- `--fps` shows a frame-rate counter, `--window` runs in a 1024x768 Wine desktop window instead
  of full screen.
- The first start is slower. Battle resolution is set in the game under **Options > Video**;
  800x600 is the tested setting. Leave the options pages with the page-corner button (Escape
  does not save them) and quit the game through its menu so the setting is kept.
- Logs: `~/mtw/logs/play-*.log`.

## What the setup changes outside `~/mtw`

The game's own changes take effect only when the game runs. The patched Mesa, the d3d9lazy shim
and the Wine settings are picked up through environment variables that `play.sh` sets for the
game, plus the game's own Wine prefix. The desktop, the browser and other programs keep using the
system Mesa. Outside `~/mtw` the script only adds:

- apt packages (build tools, innoextract, xdotool, grim, tmux), installed only after a dry run
  shows that nothing would be upgraded or removed;
- Hangover as the system Wine (unless `--private-wine`);
- the two shortcuts in `~/Desktop` and `~/.local/share/applications`.

To remove the game, delete `~/mtw` and the two shortcuts. Uninstall the apt packages and Hangover
with apt like any other package.

## Known limits

- Full screen shows a white block in the left border in 4:3 menus (a Wine scaling leftover).
- Battles run at about 17–25 FPS on a Pi 4 at 800x600.
- If the Pi runs heavy background jobs (the working Pi runs an Internet-in-a-Box server), the
  game dips for a moment whenever they start. On that Pi this was eased by giving desktop
  sessions more CPU weight; it is a system change, so it is not in the script:
  `sudo systemctl set-property user.slice CPUWeight=1000` (undo: `sudo systemctl revert user.slice`).

## Pi 5

Untested. Two things to know:

- Raspberry Pi OS on a Pi 5 uses a kernel with 16 KB pages by default, which Hangover cannot run
  on. The script stops and says so. To switch to the 4 KB kernel, add the line
  `kernel=kernel8.img` to `/boot/firmware/config.txt` and reboot.
- The Mesa patch is for the V3D driver, which the Pi 5 also uses (a newer GPU generation). It
  should build and run, but its speed-up was only measured on the Pi 4.

## Troubleshooting

| Symptom | What to do |
|---|---|
| "apt would upgrade or remove the packages above" | Nothing was installed. Look at the list; rerun with `--allow-upgrades` if those changes are fine on this Pi. |
| Checksum mismatch | Delete the named file in `~/mtw/downloads` and rerun (usually a broken download). |
| A step failed | Fix the cause and rerun the same command; finished steps are skipped. To redo a finished step, delete its marker in `~/mtw/.setup/` (`apt`, `hangover`, `game`, `shim`, `mesa`, `prefix`). |
| Game window black 640x480 in `--window` mode | A full-screen run was killed hard and left a Wine setting behind. Run `WINEPREFIX=~/mtw/prefixes/hangover /usr/bin/wine reg delete 'HKCU\Software\Wine\X11 Driver' /v EmulateModeset /f`. |
| "this Pi already has a Wine" | Nothing was installed. See [Already using Wine?](#already-using-wine); usually rerun with `--private-wine`. |
| "The game is already running" | `WINEPREFIX=~/mtw/prefixes/hangover /usr/bin/wineserver -k` (with `--private-wine`: `~/mtw/hangover/usr/bin/wineserver -k`) |

## What is not in the repo

The repo at https://github.com/KidKlatt/TWM_Pi holds only what the setup needs. The game is not
included: it is licensed to each owner, so everyone brings their own GOG installer. The
development record (experiment log, test harness, research scripts) is not published; a summary
is in [HOW-IT-WAS-MADE.md](HOW-IT-WAS-MADE.md).
