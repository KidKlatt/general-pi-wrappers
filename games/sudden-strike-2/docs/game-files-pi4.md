# Pi 4 game files

## GOG offline installer source

Inventoried on the Windows PC on 2026-11-16. Each game is a single-file offline installer in
`Game Files/GOG Offline installer/`.

| Game | File | Bytes | SHA-256 |
|---|---|---:|---|
| Sudden Strike 2 | `setup_sudden_strike_2_2.2_(13718).exe` | 623,071,288 | `b78b6c41678352babb5eb15a855c3ea3e78dcb10309cfc973a8bbe653f5f8109` |
| Sudden Strike: Resource War | `setup_sudden_strike_resource_war_2.4_(13581).exe` | 476,182,376 | `13eb17aabde8031175fe10d88623b40fada3500b3abb663ed1132f095d785fff` |

Total: 1,099,253,664 bytes. Both files were copied to `~/ss2/installer/`; their Pi SHA-256 hashes
match the PC values above (verified 2026-11-16).

Extraction tool on the Pi: `innoextract 1.9`. Both installers are Inno Setup 5.5.7 (unicode).

## Extracted games

Native extraction succeeded on 2026-11-16 (experiment 3):

```sh
cd ~/ss2
innoextract --gog -s -d game-ss2 'installer/setup_sudden_strike_2_2.2_(13718).exe'
innoextract --gog -s -d game-rw  'installer/setup_sudden_strike_resource_war_2.4_(13581).exe'
# innoextract puts the game in <dir>/app and installer temp files in <dir>/tmp
for g in game-ss2 game-rw; do mv $g $g.x && mv $g.x/app $g && rm -rf $g.x; done
cp -al game-ss2 game-ss2.pristine; cp -al game-rw game-rw.pristine
```

`tmp/` held only installer material (DirectX June 2010 redistributable, EULAs, installer DLLs).

| | Sudden Strike 2 (`game-ss2`) | Resource War (`game-rw`) |
|---|---|---|
| Files / bytes | 905 / 511,502,745 | 124 / 384,474,588 |
| Game version | 2.2 | 2.4 (patch 1, mp_fix, bonus campaign) |
| Main executable (GOG play task) | `game_exe.exe` (76 KiB, PE32 GUI i386) | `game_exe.exe` (64 KiB) |
| Window title | `Sudden Strike version 2.0` | `Sudden Strike - Resource War` |
| Editor | `edit3.exe` | `edit3.exe` |
| Settings file | `sudtest.ini` | `sudtest.ini` |
| Saves | `plr\savegames\<player>\` inside the game folder | same |

`game_exe.exe` is a small loader; `sudtest.ini` names the modules it loads (`n2Menu_dll.dll`,
`n2Game_Dll.dll`, `n2Text_dll.dll`) and the drawing module per resolution (`SSDraw1..3` =
`n2Cad640/800/1024.dll`, the only files that import `DDRAW.dll`).

### What the GOG installer does besides copying files

From `goggame-<id>.script` in each game folder:

- **Sudden Strike 2:** (1) installs a Windows compatibility database `__support/add/goggame.sdb`
  (Windows-only, not applicable under Wine; the play task's flags are `DWM8And16BitMitigation
  WINXPSP2 HIGHDPIAWARE DISABLEDWM`); (2) copies `__support/winmm_override/` over the game
  folder: a `n2Game_Dll.dll` that imports `WIN32.dll` instead of `WINMM.dll`, plus that
  `win32.dll` (imports `libvorbisfile-3.dll`; presumably plays `MUSIC/Track*.ogg` in place of CD
  audio). **Step 2 was done by hand** in `game-ss2` (not in the pristine copy), so `game-ss2`
  equals an installed game.
- **Resource War:** no actions. It already ships `winmm.dll` (a similar wrapper) in its folder.
- No registry entries in either script.

Sudden Strike 2 also ships a GOG `ddraw.dll` (1.22 MiB, imports `d3d9.dll`, "DirectDraw/Direct3D")
in the game folder. It is now renamed `ddraw.dll.gog` in the working copy (cnc-ddraw took its
name) and is not used; forum reports on Windows say the game is smoother without it.

### Changes made to the working copies

- `sudtest.ini` in both: `VideoMode=3` → `VideoMode=2` (800x600), because the Pi desktop was
  1280x720 and a 1024x768 window does not fit. `FullScreen=1` unchanged.
- cnc-ddraw 7.1.0.0 (`ddraw.dll`, `ddraw.ini` from `config/cnc-ddraw/`, `Shaders/`) added to
  both working folders by `scripts/pi/install-cnc-ddraw.sh` (experiment 12). Sudden Strike 2's
  GOG `ddraw.dll` is kept beside it as `ddraw.dll.gog`. It is only loaded when
  `WINEDLLOVERRIDES` contains `ddraw=n` (`play.sh` default mode).
- The games write settings and player data into their own folders; restore from `.pristine` for
  a clean state (then redo the winmm step for Sudden Strike 2, the `VideoMode` edit and
  `install-cnc-ddraw.sh`).
