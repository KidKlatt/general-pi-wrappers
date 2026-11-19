# Pi 4 game files

## GOG offline installer source

Inventoried on the Windows PC on 2026-11-17. A single-file offline installer in
`Game Files/GOG Offline installer/`.

| Game | File | Bytes | SHA-256 |
|---|---|---:|---|
| Shogun: Total War (Warlord Edition) | `setup_shogun_total_wartm_gog_v1_(86790).exe` | 1,564,964,984 | `bed36e39c45bc447f21a25c7de5f3f09a09587ac176129cd3621fe9c5f216b28` |

Installer type: Inno Setup 5.6.2 (unicode), from the header string in the file.

Copied to `~/stw/installer/` on 2026-11-17 (17 s over the LAN); the Pi's SHA-256 matches.

## Extracted game

Native extraction succeeded on 2026-11-17 (experiment 3), about 1 minute:

```sh
cd ~/stw
innoextract --gog -l installer/*.exe > logs/innoextract-list.txt   # 3705 lines
innoextract --gog --language=en-US -d game.x 'installer/setup_shogun_total_wartm_gog_v1_(86790).exe'
mv game.x game
mkdir -p installer-extras
mv game/__redist game/tmp game/commonappdata installer-extras/   # redistributables, installer UI
mv game/app/* game/ && rmdir game/app   # 4 small files the installer puts in {app}
cp -al game game.pristine
```

Unlike the Sudden Strike installers, almost all game files come out at the top level, not in
`app/`; only `expansion.dat` and `ZVerify.Txt` (both 0 bytes), the icon and `webcache.zip` are
in `app/`. Without `--language` innoextract writes all four languages over each other
("overwritten"); with `en-US` only the English `ReadMe.htm`, `lang.cfg` (content `0`) and
`goggame-*.info` are written.

Result: `~/stw/game`, 3,734 files, 1,814,089,787 bytes; `~/stw/game.pristine` hard links.
`~/stw/installer-extras/` holds `__redist/` (DirectX June 2010 redistributable, MSVC 2010/2013/
2015 runtimes, GOG's `ISI/scriptinterpreter.exe`), the installer UI files and GOG's uninstaller.
None of these are installed.

## What the game folder contains

| File | What it is |
|---|---|
| `shogun.exe` (45,056 B, 2001) | GOG play task. A tiny launcher: imports only KERNEL32/USER32/SHELL32, its strings are `ShogunM.exe` and `-thread:%d`. |
| `ShogunM.exe` (7,319,552 B, PE32, built 2015-05-12) | **The game.** Imports `D3D9.dll`, `DDRAW.dll`, `DSOUND.dll`, `WINMM.dll`, `AVIFIL32.dll`, `WSOCK32.dll`, `ole32.dll`, `IMM32.dll` and the three `wea*.dll` online-chat DLLs that ship with it. |
| `ddraw.dll` (22,016 B, 2012) | A DirectDraw proxy wrapper shipped by GOG (classes `myIDDraw1`…; exports `DirectDrawCreate/Ex` and friends; needs `MSVCR100.dll`, which Wine has built in). Not loaded unless `ddraw` is overridden to native; whether the game needs it is open. |
| `Drvmgt.dll` (2001) | Leftover of the retail disc protection; nothing imports it. |
| `Movies/*.mpg` | Intro and campaign movies in MPEG-1, played through `AVIFIL32`/DirectShow, i.e. winegstreamer under Wine. |
| `shogunfe.cfg` (binary) | Front-end settings; the game also names `shoguncgj.cfg`, `shoguncgm.cfg`, `LogonDetails.cfg`, `MultiplayerDetails.cfg`. |
| `savegames/`, `logfiles/` | Save and log folders inside the game folder. |
| `Internet.cfg` | Old EA chat/news servers (dead). |

GOG play tasks (`goggame-1874325037.info`): primary `shogun.exe`, plus a support URL. One
program serves both the base game and the Mongol Invasion expansion (`expansion.dat` present);
there is no separate expansion executable.

Registry: `ShogunM.exe` contains `Software\Electronic Arts\EA Games\SHOGUN TOTAL WAR WARLORDS
EDITION PCCD\ergc` (the retail CD-key value). The installer's registry entries cannot be read
with innoextract 1.9 (its setup header is compressed and innoextract does not print registry
sections), and no GOG script file was found among the extracted files. Whether the game needs
that key is unknown; it is a Group 1 knob if the game refuses to start.
