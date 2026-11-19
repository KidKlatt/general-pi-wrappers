# Setting up Shogun: Total War on a new Raspberry Pi

One script, [`scripts/pi/setup-new-pi.sh`](../scripts/pi/setup-new-pi.sh), repeats the working
Pi 4 setup: Box64 + Wine 9.17 (x86-64, WoW64), this project's own `winex11.so` and `dsound.dll`,
the d3d9lazy shim, a private patched Mesa, and the full-screen launcher `play.sh` with desktop
shortcuts. It needs nothing from any other project: every component is downloaded from its
official source with a pinned SHA-256 and built on the Pi. Budget about an hour on a Pi 4.

## What you need

| | |
|---|---|
| Pi | Raspberry Pi 4 (tested, 4 GB). A Pi 5 needs the 4 KB-page kernel (below) and has not been tried. |
| OS | 64-bit Raspberry Pi OS / Debian 13 "trixie" with the normal desktop (labwc with Xwayland). |
| Display | Monitor on HDMI, desktop logged in. Full screen relies on Xwayland's mode emulation. |
| Disk | 12 GB free in your home folder. |
| Network | Internet: GitHub (Box64 source, Kron4ek Wine), dl.winehq.org (Wine source), archive.mesa3d.org (Mesa). |
| Game | Your GOG offline installer `setup_shogun_total_wartm_gog_v1_(86790).exe` (one file, 1.56 GB). Another GOG build may work; the script warns. |
| Account | A user with sudo (used only for apt). |

Other Wine installations are not touched: this project's Wine is a private copy in `~/stw`,
called by full path, with its own prefix.

## Steps

1. **Get the project onto the Pi.** Either clone the published wrapper on the Pi
   (`git clone https://github.com/KidKlatt/general-pi-wrappers`; the project folder is then
   `~/general-pi-wrappers/games/shogun-total-war`), or copy the working record from a PC (in its
   folder): `scp -r scripts config tools patches refs <pi>:Pi_TW_Shogun/` (folder
   `~/Pi_TW_Shogun`).
2. **Put the installer on the Pi**, for example `scp "Game Files/GOG Offline installer/setup_shogun_total_wartm_gog_v1_(86790).exe" <pi>:gog/`
3. **Run the setup** on the Pi, in tmux (SSH sessions can drop):
   ```sh
   tmux new -s stw
   bash <project folder>/scripts/pi/setup-new-pi.sh --installer ~/gog
   ```
   It copies the project to `~/stw`, installs missing apt packages (simulated first; it stops if
   anything would be upgraded or removed, override with `--allow-upgrades`), builds Box64, unpacks
   Wine, builds `dsound.dll` and `winex11.so` from the Wine source, builds Mesa, unpacks the game,
   adds the shim, creates the Wine prefix and puts two shortcuts on the desktop. If a step fails,
   fix the cause and run the same command again: finished steps are skipped (markers in
   `~/stw/.setup/`).
4. **Play**: double-click "Shogun Total War" on the desktop. The first start takes longer.

## After the setup

- In the game, Options > Video: a 16:9 battle resolution fills the screen without stretching
  (menus are 800x600 and are stretched). The human tested a lower 16:9 mode on the Pi 4.
- Sound: the game's sound runs through a cheaper resampler (needed for battle frame rates).
- If the Pi also runs heavy background jobs, battles dip for a few seconds when they run. The
  development Pi has `user.slice` CPUWeight=1000 (set for MTW); the setup does not change it.
- Removing everything, versions and checks: [RUNBOOK.md](RUNBOOK.md).

## Pi 5

`getconf PAGESIZE` must print 4096. Pi 5 kernels default to 16 KB pages: add `kernel=kernel8.img`
to `/boot/firmware/config.txt` and reboot, then run the setup. The patched Mesa targets the
Pi 4's V3D 4.2; on a Pi 5 try without it first (remove the four Mesa lines from
`config/profile-final-pi4.env`). Box64 is built with `-DRPI4ARM64=1`; for a Pi 5 use
`-DRPI5ARM64=1` (edit step 4 of the script).
