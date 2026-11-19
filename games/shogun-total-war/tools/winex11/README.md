# winex11.so for this project (Wine 9.17, x86-64)

Two changes: no XLockDisplay around GLX calls, the fix for the campaign-start hang (experiments
43-45, 52-56), and full-screen mode changes on Xwayland (experiment 58, below). It is installed only
in this project's own Wine copy, `~/stw/wine-x64-9.17` (Kron4ek's vanilla
`wine-9.17-amd64-wow64` build, downloaded by `scripts/pi/setup-new-pi.sh`).

**The deadlock.** Entering the campaign map, Shogun switches from Direct3D 9 to DirectDraw. Wine's
DirectDraw device creates an OpenGL context: winex11 `glxdrv_wglCreateContextAttribsARB` calls
`X11DRV_expect_error`, which takes `XLockDisplay(gdi_display)` until `X11DRV_check_error`, and in
between Mesa sends `glXCreateContextAttribsARB` through xcb. If the Direct3D 9 device's GL thread
is meanwhile in `glXSwapBuffers` (Mesa DRI3, `xcb_present_pixmap`) and Xlib owns the socket, xcb
runs Xlib's `return_socket`, which waits for the XLockDisplay, while the locked thread waits in xcb
for the socket. Evidence: `runs/20261118-153255-box64-repro-1/hang/`.

**The change** (`apply-gl-nolock.py`, run in `dlls/winex11.drv`; the same as
`wine-9.17-winex11-gl-nolock.patch`): new `X11DRV_expect_error_nolock` /
`X11DRV_check_error_nolock` in `x11drv_main.c` (same error mutex, callback and request serial, no
XLockDisplay), used by the three GL sites in `opengl.c` (`set_swap_interval` EXT,
`wglCopyContext`, `wglCreateContextAttribsARB`). `GLXErrorHandler` only swallows errors with the
GLX opcode, so another thread's error in that window still reaches the normal handler. All
other `X11DRV_expect_error` users (XShm, XRandR, XVidMode, clipboard, tablet) make pure Xlib calls
and keep the lock. The log prints `STW winex11 build: GL error checks without XLockDisplay` at the
first context creation.

**Build on the Pi** (about 5 minutes after configure; uses the `tools/dsound` source tree and its
native `build/` directory for the Wine build tools):

```sh
# cross compiler and X extension headers (simulated first: 22 + 2 + 4 new packages, 0 changed)
sudo apt-get install --no-install-recommends gcc-x86-64-linux-gnu libc6-dev-amd64-cross \
  libxi-dev libxinerama-dev libxcursor-dev libxcomposite-dev
bash ~/stw/tools/winex11/mkcross.sh          # x86-64 LINK STUBS for the 12 X/GL/Vulkan sonames
cd ~/stw/src/wine-9.17/dlls/winex11.drv && python3 -I ~/stw/tools/winex11/apply-gl-nolock.py \
  && python3 -I ~/stw/tools/winex11/apply-xwayland-modeset.py
mkdir -p ~/stw/src/wine-9.17/build64 && cd ~/stw/src/wine-9.17/build64
X=$HOME/stw/src/x11cross
../configure --host=x86_64-linux-gnu --with-wine-tools=../build --without-mingw --disable-tests \
  --with-x --x-includes=$X/include --x-libraries=$X/lib --with-opengl --with-vulkan \
  --without-freetype --without-gstreamer --without-cups --without-dbus --without-gphoto --without-sane \
  --without-krb5 --without-netapi --without-pcap --without-pcsclite --without-sdl --without-usb \
  --without-v4l2 --without-wayland --without-gnutls --without-alsa --without-pulse --without-oss \
  --without-capi --without-unwind --without-udev --without-inotify --without-ffmpeg \
  --without-coreaudio --without-osmesa --without-fontconfig --without-gssapi \
  CFLAGS="-O2 -g" LDFLAGS="-L$X/lib"
make -j3 dlls/winex11.drv/winex11.so
U=~/stw/wine-x64-9.17/lib/wine/x86_64-unix
cp -n $U/winex11.so $U/winex11.so.kron4ek && cp dlls/winex11.drv/winex11.so $U/winex11.so
```

The stubs are never loaded: Box64 maps the sonames (`libX11.so.6`, ...) to its native wrappers at
run time, exactly as for the original build. Checked against the original: same needed X
libraries and unix call tables (5 + 5 entries); function names differ only by inlining (GCC 14
against 11) plus the two new functions. SHA-256 of the result with both
changes: `cf09bd103265c45884c5071d2ada6f1879ab32fe98fb821a4fbd09992f7f3fb1`; with the GL change
only (kept as `winex11.so.gl-nolock`):
`e1bda0179fb859d969f1dda50e0c51c2b981474493aab1785667bf8ae44d3587`; original
(`winex11.so.kron4ek`): `6216af3087fdd82248187f55107200a05681a8353571f93e5622986dcc5a5044`.

**Full screen on Xwayland** (`apply-xwayland-modeset.py`). Wine 9.17 changes a display mode by
disabling the CRTC, resizing the X screen, then setting the mode; Xwayland refuses the first two
(`RRSetScreenSize` BadMatch), so the game's 800x600 / 640x480 requests did nothing and the
picture sat unscaled in the screen corner (Wine 9.17 has no `EmulateModeset`, which MTW's newer
Wine uses). On Xwayland (XWAYLAND extension present) the patched `xrandr14_set_current_mode`
makes one `XRRSetCrtcConfig` with the requested mode, on the calling thread's X connection.
Xwayland keeps that as an emulated mode for that X client only and scales the client's window
of exactly that size at 0,0 to the whole output (wp_viewporter, which labwc offers). It must be
the thread's connection: the game window belongs to it, and Wine's shared `gdi_display` is a
different X client (the first try, which scaled nothing). Xwayland scales the pointer back. Other
programs and the real screen mode are untouched; the emulation ends with the game. The picture is
stretched from 4:3 to 16:9. Run without a Wine desktop (`config/profile-10-fullscreen.env`); the
Wine-desktop mode the harness uses does not go through this code. The log prints `STW winex11
build: Xwayland mode changes by emulation` at the first mode change.

To go back: `cp $U/winex11.so.kron4ek $U/winex11.so` (or `.gl-nolock` to keep only the hang fix). Wine is LGPL 2.1+: the patch and this note
are the source for the change.
