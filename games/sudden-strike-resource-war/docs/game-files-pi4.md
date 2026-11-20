# Pi 4 game files

## GOG offline installer source

Inventoried on the Windows PC on 2026-11-16 (in the SS2 project). Single-file offline installer in
`Game Files/GOG Offline installer/`.

| Game | File | Bytes | SHA-256 |
|---|---|---:|---|
| Sudden Strike: Resource War | `setup_sudden_strike_resource_war_2.4_(13581).exe` | 476,182,376 | `13eb17aabde8031175fe10d88623b40fada3500b3abb663ed1132f095d785fff` |

On the Pi it is in `~/ssrw/installer/` (moved from `~/ss2/installer/` on 2026-11-20); the Pi
SHA-256 matches the value above (checked 2026-11-16 and again 2026-11-20).
`goggame-1707288232.info`: `gameId` 1707288232, `buildId` 50348383013086683.

Extraction tool on the Pi: `innoextract 1.9`. The installer is Inno Setup 5.5.7 (unicode).

## Extracted game

Extracted on 2026-11-16 (SS2 project, experiment 3) as `~/ss2/game-rw`, moved to `~/ssrw/game`
on 2026-11-20. The same steps for a fresh install:

```sh
cd ~/ssrw
innoextract --gog -s -d game 'installer/setup_sudden_strike_resource_war_2.4_(13581).exe'
# innoextract puts the game in <dir>/app and installer temp files in <dir>/tmp
mv game game.x && mv game.x/app game && rm -rf game.x
cp -al game game.pristine
```

`tmp/` held only installer material (DirectX June 2010 redistributable, EULAs, installer DLLs).

| | Resource War (`game`) |
|---|---|
| Files / bytes | 124 / 384,474,588 |
| Game version | 2.4 (patch 1, mp_fix, bonus campaign) |
| Main executable (GOG play task) | `game_exe.exe` (64 KiB, PE32 GUI i386) |
| Window title | `Sudden Strike - Resource War` |
| Editor | `edit3.exe` |
| Settings file | `sudtest.ini` |
| Saves | `plr\savegames\<player>\` inside the game folder |

`game_exe.exe` is a small loader; `sudtest.ini` names the modules it loads (`n2Menu_dll.dll`,
`n2Game_Dll.dll`, `n2Text_dll.dll`) and the drawing module per resolution (`SSDraw1..3` =
`n2Cad640/800/1024.dll`, the only files that import `DDRAW.dll`).

## What the GOG installer does besides copying files

From `goggame-1707288232.script`: no actions and no registry entries. Unlike Sudden Strike 2 there
is no `winmm_override` step; the game already ships its own `winmm.dll` music wrapper (with
`libvorbisfile-3.dll`) in its folder.

## Changes made to the working copy

- `sudtest.ini`: `VideoMode=3` → `VideoMode=2` (800x600), because the Pi desktop is 1280x720.
  `FullScreen=1` unchanged.
- cnc-ddraw 7.1.0.0 (`ddraw.dll`, `ddraw.ini` from `config/cnc-ddraw/`, `Shaders/`) added by
  `scripts/pi/install-cnc-ddraw.sh`. It is only loaded when `WINEDLLOVERRIDES` contains
  `ddraw=n` (`play.sh` default mode).
- The game writes settings and player data into its own folder; restore from `game.pristine` for
  a clean state (then redo the `VideoMode` edit and `install-cnc-ddraw.sh`).
