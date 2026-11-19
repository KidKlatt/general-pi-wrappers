#!/usr/bin/env python3
"""Patch Wine 9.17 dlls/winex11.drv/xrandr.c (run in that directory, after apply-gl-nolock.py)
so that full-screen mode changes work on Xwayland (experiment 58, tools/winex11/README.md).

Wine 9.17's xrandr14_set_current_mode() first disables the CRTC and resizes the X screen, then
sets the new mode. Xwayland refuses the CRTC disable and the screen resize (RRSetScreenSize
BadMatch), so the game's 800x600 or 640x480 request never takes effect and the picture sits
unscaled in the screen corner. Xwayland does support mode changes on its own terms: a single
RRSetCrtcConfig with one of its listed modes sets an *emulated* mode for that X client (X
connection) only, and Xwayland then scales that client's top-level window to the whole output
if the window has exactly the mode's size at the output's origin (wp_viewporter). This patch takes that single call on
Xwayland (detected by its XWAYLAND extension), on the calling thread's X connection (the one that
owns the game window; Wine's shared gdi_display is a different client); on any other X server
nothing changes.
No registry setting is needed: Wine places the game's full-screen window at 0,0 with the mode's
size and labwc leaves it there. (Managed=N was tried and is harmful: labwc then gives the
window no focus, wined3d restores the desktop mode and the game crashes in StretchRect.)
"""

def sub(path, old, new, count=1):
    s = open(path, encoding="utf-8").read()
    assert s.count(old) == count, f"{path}: expected {count} of {old!r}, found {s.count(old)}"
    s = s.replace(old, new)
    open(path, "w", encoding="utf-8", newline="\n").write(s)

sub("xrandr.c", """static LONG xrandr14_set_current_mode( x11drv_settings_id id, const DEVMODEW *mode )
{""", """/* STW project build (Pi_TW_Shogun tools/winex11): Xwayland only accepts a plain RRSetCrtcConfig
 * with one of its modes, which it emulates for this client and scales to the output. */
static BOOL xrandr_is_xwayland(void)
{
    static int is_xwayland = -1;
    int opcode, event, error;

    if (is_xwayland < 0)
    {
        is_xwayland = XQueryExtension( gdi_display, "XWAYLAND", &opcode, &event, &error ) ? 1 : 0;
        if (is_xwayland) ERR( "STW winex11 build: Xwayland mode changes by emulation\\n" );
    }
    return is_xwayland;
}

static LONG xrandr14_set_current_mode( x11drv_settings_id id, const DEVMODEW *mode )
{""")

sub("xrandr.c", """    rotation = get_rotation( mode->dmDisplayOrientation );

    /* According to the RandR spec, the entire CRTC must fit inside the screen.""",
"""    rotation = get_rotation( mode->dmDisplayOrientation );

    if (xrandr_is_xwayland())
    {
        /* Xwayland keeps the emulated mode per X client and scales only that client's windows,
         * so set it on this thread's connection, which owns the game's window. */
        Display *display = thread_init_display();
        status = pXRRSetCrtcConfig( display, screen_resources, crtc, CurrentTime,
                                    mode->dmPosition.x, mode->dmPosition.y, rrmode,
                                    rotation, outputs, output_count );
        XSync( display, False );
        TRACE( "Xwayland emulated mode %ux%u: status %d\\n", (int)mode->dmPelsWidth,
               (int)mode->dmPelsHeight, status );
        if (status == RRSetConfigSuccess)
            ret = DISP_CHANGE_SUCCESSFUL;
        goto done;
    }

    /* According to the RandR spec, the entire CRTC must fit inside the screen.""")
print("patched")
