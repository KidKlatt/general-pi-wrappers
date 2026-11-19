#!/usr/bin/env python3
"""Patch Wine 9.17 dlls/winex11.drv (run in that directory) for the campaign-start deadlock
(experiment 52, tools/winex11/README.md).

X11DRV_expect_error() takes XLockDisplay() until X11DRV_check_error(). Around a GLX call that
Mesa sends through xcb (glXCreateContextAttribsARB, glXSwapIntervalEXT, glXCopyContext) this
deadlocks with a Mesa DRI3 buffer swap on another thread: the swap's xcb call needs Xlib's
return_socket(), which waits for the XLockDisplay, while the locked thread waits in xcb for the
socket. The three GL sites in opengl.c therefore use X11DRV_expect_error_nolock() /
X11DRV_check_error_nolock(): same error_mutex, callback and serial, but no XLockDisplay.
GLXErrorHandler only swallows errors with the GLX major opcode, so another thread's non-GLX error
in that window still reaches the normal handler. All other users are unchanged.
"""
import re

def sub(path, old, new, count=1):
    s = open(path, encoding="utf-8").read()
    assert s.count(old) == count, f"{path}: expected {count} of {old!r}, found {s.count(old)}"
    s = s.replace(old, new)
    open(path, "w", encoding="utf-8", newline="\n").write(s)

sub("x11drv_main.c", """/***********************************************************************
 *		X11DRV_check_error
""", """/* STW project build (Pi_TW_Shogun tools/winex11): as X11DRV_expect_error without XLockDisplay,
 * for GLX calls that Mesa sends through xcb (see tools/winex11/README.md). */
void X11DRV_expect_error_nolock( Display *display, x11drv_error_callback callback, void *arg )
{
    pthread_mutex_lock( &error_mutex );
    err_callback         = callback;
    err_callback_display = display;
    err_callback_arg     = arg;
    err_callback_result  = 0;
    err_serial           = NextRequest(display);
}

int X11DRV_check_error_nolock(void)
{
    int res = err_callback_result;
    err_callback = NULL;
    pthread_mutex_unlock( &error_mutex );
    return res;
}


/***********************************************************************
 *		X11DRV_check_error
""")

sub("x11drv.h", "extern int X11DRV_check_error(void);",
    "extern int X11DRV_check_error(void);\n"
    "extern void X11DRV_expect_error_nolock( Display *display, x11drv_error_callback callback, void *arg );\n"
    "extern int X11DRV_check_error_nolock(void);")

s = open("opengl.c", encoding="utf-8").read()
n_e = s.count("X11DRV_expect_error")
n_c = s.count("X11DRV_check_error")
assert n_e == 3 and n_c == 3, (n_e, n_c)
s = re.sub(r"X11DRV_expect_error\b", "X11DRV_expect_error_nolock", s)
s = re.sub(r"X11DRV_check_error\b", "X11DRV_check_error_nolock", s)
# Marker so a log line shows that this build is in use (once, at the first context creation).
old = "        ret->ctx = create_glxcontext(gdi_display, ret, hShareContext ? hShareContext->ctx : NULL);"
assert s.count(old) == 1
s = s.replace(old, """        {
            static int once;
            if (!once++) ERR( "STW winex11 build: GL error checks without XLockDisplay\\n" );
        }
""" + old)
open("opengl.c", "w", encoding="utf-8", newline="\n").write(s)
print("patched")
