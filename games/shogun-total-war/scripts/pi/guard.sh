#!/usr/bin/env bash
# Protects the existing server role of the Pi.
#   guard.sh snapshot   record running services, listening ports, installed packages (once)
#   guard.sh check      fail if a baseline service stopped, a baseline port closed,
#                       or a baseline package was removed or changed version
set -u
B="${STW_HOME:-$HOME/stw}/baseline"
services() { systemctl list-units --type=service --state=running --no-legend --plain | awk '{print $1}' | sort; }
ports()    { ss -tlnH | awk '{print $4}' | sed 's/.*://' | LC_ALL=C sort -u; }
packages() { dpkg-query -W -f='${Package}:${Architecture} ${Version}\n' | sort; }

case "${1:-}" in
  snapshot)
    if [ -e "$B/services.txt" ] && [ "${2:-}" != "--force" ]; then
      echo "Baseline already exists in $B (use --force to replace it; ask the human first)"; exit 1
    fi
    mkdir -p "$B"
    services >"$B/services.txt"; ports >"$B/ports.txt"; packages >"$B/packages.txt"
    date -Is >"$B/taken"
    echo "Baseline saved: $(wc -l <"$B/services.txt") services, $(wc -l <"$B/ports.txt") ports, $(wc -l <"$B/packages.txt") packages"
    ;;
  check)
    [ -e "$B/services.txt" ] || { echo "No baseline. Run: guard.sh snapshot"; exit 2; }
    fail=0
    # Transient units (sessions, one-shot user managers) are ignored.
    lost=$(comm -23 <(grep -Ev '^(user@|session-|systemd-hostnamed|systemd-timedated|packagekit)' "$B/services.txt") <(services))
    [ -n "$lost" ] && { echo "SERVICES NO LONGER RUNNING:"; echo "$lost"; fail=1; }
    closed=$(comm -23 <(LC_ALL=C sort -u "$B/ports.txt") <(ports))
    [ -n "$closed" ] && { echo "PORTS NO LONGER LISTENING:"; echo "$closed"; fail=1; }
    changed=$(comm -23 "$B/packages.txt" <(packages))
    [ -n "$changed" ] && { echo "BASELINE PACKAGES REMOVED OR CHANGED:"; echo "$changed"; fail=1; }
    added=$(comm -13 "$B/packages.txt" <(packages) | wc -l)
    echo "Packages added since baseline: $added"
    df -h "$HOME" | awk 'NR==2{print "Free under home: "$4}'
    [ "$fail" = 0 ] && echo "GUARD OK" || echo "GUARD FAILED"
    exit "$fail"
    ;;
  *) echo "usage: guard.sh snapshot [--force] | check"; exit 2 ;;
esac
