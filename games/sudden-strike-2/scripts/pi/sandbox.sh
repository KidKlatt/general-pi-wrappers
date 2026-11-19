#!/usr/bin/env bash
# sandbox.sh: run an untrusted Windows tool (the closed-source SS2 resolution patcher) under Wine
# inside bubblewrap. Approved by the human 2026-11-17 for this one tool, on copies only.
#   sandbox.sh start <exe-path-inside> [args]   start Xvfb + wine <exe> in the sandbox (tmux ss2sb)
#   sandbox.sh ctl <command...>                  run a command (xdotool, import...) against the
#                                                sandbox's screen, in a second sandbox
#   sandbox.sh shell <command...>                run a command inside a fresh sandbox (same home)
#   sandbox.sh stop
# Isolation: no network (--unshare-all), no access to the real home: $SB/root is mounted as
# /home/admin and is the only writable place besides tmpfs /tmp; system dirs are read-only; the
# sandbox's own Xvfb screen :55 has its socket in $SB/x11 (the real desktop is not reachable).
# Inputs go in $SB/root/in, outputs come out of $SB/root (inspect them before using anything).
set -eu
SB="${SB:-$HOME/ss2/sandbox/patcher}"
mkdir -p "$SB/root" "$SB/x11"
bw() {
  bwrap --unshare-all --die-with-parent --new-session \
    --ro-bind /usr /usr --symlink usr/bin /bin --symlink usr/sbin /sbin \
    --symlink usr/lib /lib --ro-bind /etc /etc --ro-bind /sys /sys \
    --proc /proc --dev /dev --tmpfs /tmp --tmpfs /run \
    --bind "$SB/x11" /tmp/.X11-unix \
    --bind "$SB/root" /home/admin --chdir /home/admin \
    --clearenv --setenv HOME /home/admin --setenv USER admin --setenv PATH /usr/bin:/usr/sbin \
    --setenv DISPLAY :55 --setenv WINEPREFIX /home/admin/prefix --setenv WINEDEBUG -all \
    --setenv LANG C.UTF-8 \
    "$@"
}
case "${1:-}" in
  start)
    shift
    tmux kill-session -t ss2sb 2>/dev/null || true
    rm -f "$SB/x11/X55"
    printf '%q ' "$@" > "$SB/root/.cmd"
    tmux new-session -d -s ss2sb "$(declare -f bw); SB='$SB'; bw bash -c 'Xvfb :55 -screen 0 1280x800x24 -nolisten tcp >/home/admin/xvfb.log 2>&1 & sleep 2; [ -d prefix ] || wineboot -i >/home/admin/wineboot.log 2>&1; eval wine \$(cat .cmd) >/home/admin/wine.log 2>&1; sleep 99999' "
    echo started ;;
  ctl)  shift; bw --setenv XAUTHORITY /dev/null "$@" ;;
  shell) shift; bw "$@" ;;
  stop) tmux kill-session -t ss2sb 2>/dev/null || true; rm -f "$SB/x11/X55"; echo stopped ;;
  *) echo "usage: sandbox.sh start|ctl|shell|stop"; exit 2 ;;
esac
