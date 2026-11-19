# TWM_Pi

Play **Medieval: Total War** (the GOG release, 2002, 32-bit x86, Direct3D) on a Raspberry Pi 4
through x86 emulation and Wine (Hangover 11.16 with its Box64-based WowBox64 emulator). **You need
your own copy of the game**; this repo holds only the setup scripts, configuration, a small
Direct3D 9 helper DLL of our own, and a patch for the Pi's Mesa graphics driver. The game files are
not modified.

On a Pi 4 it runs full screen at about 17–25 FPS in battles (800x600).  This is surprisingly playable and smooth.

## Quick start

You need:
- a Raspberry Pi 4 with 64-bit Raspberry Pi OS / Debian 13 "trixie" and its desktop;
- about 10 GB free;
- your own GOG copy of the game as the **offline backup installer**, which is **two files**: the
  `setup_medieval_total_war_….exe` and its `….bin`. Download both from your GOG library.

Put **both** installer files in a folder called `gog` in your home folder on the Pi (`~/gog`),
then run:

```bash
git clone https://github.com/KidKlatt/TWM_Pi ~/pi-total-war
tmux new -s setup
bash ~/pi-total-war/scripts/pi/setup-new-pi.sh --installer ~/gog
```

> **Already use Wine on this Pi for other programs?** The setup installs Hangover as the system
> Wine, which replaces a Wine package from apt. The script detects this and stops; rerun it with
> `--private-wine` to keep your Wine. Details: [Already using Wine?](docs/NEW-PI-SETUP.md#already-using-wine)

About 45 minutes later, start the game from the **Medieval Total War** desktop shortcut. The full
guide, including Pi 5 notes and troubleshooting, is [docs/NEW-PI-SETUP.md](docs/NEW-PI-SETUP.md).

## License

This project's own scripts, configuration, docs and shim source are under the [MIT license](../../LICENSE).
It builds on other projects (Hangover/Wine/Box64, Mesa and others) that have their own licenses,
and the game itself is commercial and not included. **Check the licenses of the projects involved
before you reuse or redistribute anything;** see [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

## How it was made

Worked out by coding agents in about 140 measured experiments. The short story, including what
made it fast, is in [docs/HOW-IT-WAS-MADE.md](docs/HOW-IT-WAS-MADE.md).
