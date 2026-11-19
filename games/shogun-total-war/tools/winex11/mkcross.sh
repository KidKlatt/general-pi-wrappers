#!/usr/bin/env bash
# Prepare an x86-64 cross build of Wine 9.17's winex11.so on the Pi (aarch64), no amd64 multiarch.
#   mkcross.sh            -> $STW_HOME/src/x11cross/{include,lib} (STW_HOME default ~/stw)
# include/: links to the (architecture-independent) X11, GL, KHR and xcb headers in /usr/include.
# lib/:     x86-64 LINK STUBS: for each library the Kron4ek winex11.so needs, an empty x86-64
#           shared object with the same soname and the same exported function names as the Pi's
#           arm64 library (taken with nm -D). They only satisfy configure and the linker; at run
#           time Box64 maps these sonames to its native wrappers, exactly as for the original
#           build, so the stubs are never loaded.
set -eu
X=${STW_HOME:-$HOME/stw}/src/x11cross
mkdir -p "$X/include" "$X/lib" "$X/stubsrc"
for d in X11 GL KHR xcb; do ln -sfn /usr/include/$d "$X/include/$d"; done
LIBS="X11.so.6 Xext.so.6 Xi.so.6 Xrandr.so.2 Xrender.so.1 Xinerama.so.1 Xcomposite.so.1 \
Xcursor.so.1 Xfixes.so.3 Xxf86vm.so.1 GL.so.1 vulkan.so.1"
for l in $LIBS; do
  base=${l%%.so.*}
  src=/usr/lib/aarch64-linux-gnu/lib$l
  nm -D --defined-only "$src" | awk '$2 ~ /^[TW]$/ {print $3}' | sed 's/@.*//' | sort -u \
    | awk '{printf "void %s(void) {}\n", $1}' >"$X/stubsrc/$base.c"
  nm -D --defined-only "$src" | awk '$2 ~ /^[BDRV]$/ {print $3}' | sed 's/@.*//' | sort -u \
    | awk '{printf "char %s[64];\n", $1}' >>"$X/stubsrc/$base.c"
  x86_64-linux-gnu-gcc -shared -fPIC -w -fno-builtin -o "$X/lib/lib$l" -Wl,-soname,lib$l "$X/stubsrc/$base.c"
  ln -sfn "lib$l" "$X/lib/lib$base.so"
done
ls -la "$X/lib"
