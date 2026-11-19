# dsound.dll with a linear resampler (Wine 9.17)

This project's own build of Wine 9.17's DirectSound, for Track B (Box64 + Wine 9.17).

**Why.** In Shogun battles one thread runs Wine's software sound mixer (`DSOUND_MixToPrimary`)
at 100% of a core, and the game waits for it: the same fight ran at 3.8 FPS with sound and 41 FPS
with the game muted (experiments 34-38). The game's sounds are 22050/11025 Hz and Wine mixes at
PipeWire's 48 kHz, so every playing sound goes through Wine's FIR resampler (`fir.h`: 7907
points, step 120, about 66 taps per output sample and channel), and under x86 emulation that loop
costs a core. The mix rate cannot be changed from outside: winepulse opens the PipeWire sink with
`PA_STREAM_FIX_RATE`, and dsound only uses the game's own format with `DSSCL_WRITEPRIMARY`.

**What.** `apply-linear.py` (and the equivalent `wine-9.17-dsound-linear.patch`) adds
`cp_fields_resample_linear` to `dlls/dsound/mixer.c` and uses it instead of the FIR path.
`STW_DSOUND_RESAMPLER=fir` in the environment switches back to Wine's filter with the same DLL;
the log prints `STW dsound build: linear|fir resampler` at start-up.

**Build (on the Pi, about 5 minutes after configure):**

```sh
cd ~/stw/src
curl -fsSLO https://dl.winehq.org/wine/source/9.x/wine-9.17.tar.xz   # SHA-256 3edb7eb6f31bb5c3f7378dd5623da9d95f7d4d6d7c8378afd89c8e3a30aa080c
tar -xJf wine-9.17.tar.xz
cd wine-9.17/dlls/dsound && python3 -I ~/stw/tools/dsound/apply-linear.py && cd ../..
mkdir build && cd build
../configure --enable-archs=i386 --disable-tests --without-x --without-freetype --without-gstreamer \
  --without-vulkan --without-opengl --without-cups --without-dbus --without-gphoto --without-sane \
  --without-krb5 --without-netapi --without-pcap --without-pcsclite --without-sdl --without-usb \
  --without-v4l2 --without-wayland --without-gnutls --without-alsa --without-pulse --without-oss \
  --without-capi --without-unwind --without-udev --without-inotify --without-ffmpeg \
  --without-coreaudio --without-osmesa --without-xinerama
make -j3 dlls/dsound/i386-windows/dsound.dll
cp dlls/dsound/i386-windows/dsound.dll ~/stw/tools/dsound/dsound.dll
# Wine marks DLLs it built as "builtin" (bytes 64-95: "Wine builtin DLL") and then loads its own
# system copy instead, override or not (experiment 39). Blank the marker in a copy:
cd ~/stw/tools/dsound && python3 -I -c "
d=bytearray(open('dsound.dll','rb').read()); assert d[64:80]==b'Wine builtin DLL'
d[64:96]=bytes(32); open('dsound-native.dll','wb').write(d)"
cp dsound-native.dll ~/stw/game-lazy/dsound.dll
```

Check that it is the one in use: the game log shows `STW dsound build: linear resampler`, and
`grep dsound /proc/$(pgrep -x ShogunM.exe)/maps` names `game-lazy/dsound.dll`.

Loaded with `dsound=n,b` (`config/profile-08-dsound-linear.env`). Only for Wine 9.17 (Track B);
the system Hangover Wine is not touched. Wine is LGPL 2.1+: the patch and this note are the
source for the change.
