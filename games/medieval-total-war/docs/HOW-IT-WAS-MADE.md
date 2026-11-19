# How it was made

The port was worked out over a few days in November 2026 by coding agents running on a Windows
PC and driving the Pi 4 over SSH. A human set the rules and checked the results by playing.
The agents worked in small recorded experiments: one change at a time, each measured in a
repeatable Quick Battle, then kept or dropped. There were about 140 experiments. The original Pi
also runs a home server, so the agents worked under strict rules: no system upgrades, no
changes to existing services, and everything kept inside `~/mtw`.

## What was tried

- **Emulation stacks.** Box64 with x86-64 Wine (WoW64) worked but was slow. Box86 with 32-bit
  Wine was dropped. **Hangover** (ARM64 Wine with the WowBox64 emulator) won.
- **Graphics paths.** Zink, Wine's Vulkan renderer, dxwrapper and DXVK-Sarek were rejected
  (slower, or they crashed the Pi 4's GPU). The game stayed on WineD3D over OpenGL.

## What made it fast

The first battle ran at **0.7 FPS**. The main fixes, in order:

1. **Patched Mesa V3D driver** (`patches/mesa-v3d-busy-range.patch`). The game draws about one
   triangle per call, and stock V3D flushed the GPU on every small buffer upload. The patch
   tracks which part of a buffer the GPU still needs to read, so most uploads go through without
   a flush. It is built privately into `~/mtw/mesa-patched`; the system Mesa is not touched.
2. **d3d9lazy shim** (`tools/d3d9lazy/d3d9lazy.c`, an own `d3d9.dll` placed next to the game):
   - Avoids reading the whole frame back from the GPU when the game locks it to paint interface
     pieces; only the changed pixels are drawn on top.
   - Merges the game's hundreds of tiny draws into a few large ones.
   - Runs Direct3D calls on a helper thread, so the game can run up to one frame ahead.
   - Answers the game's depth-buffer reads from a copy of the previous frame.
3. **`VideoMemorySize=512`** for WineD3D: removed the missing-sprite errors and the white
   flashing units.
4. **Full screen.** Wine's `EmulateModeset` setting scales the 4:3 picture to the display. It is
   switched on only while the game runs, because it breaks Wine's windowed-desktop mode.

Result on a Pi 4: about **17–25 FPS** in battles at 800x600. The campaign map runs much faster.

## Known rough edges

- In full screen, a white block shows in the left border of the 4:3 menus.
- Short frame-rate dips happen when other heavy programs on the Pi wake up.
- The shim's known limits are listed in the comment at the top of its source.
