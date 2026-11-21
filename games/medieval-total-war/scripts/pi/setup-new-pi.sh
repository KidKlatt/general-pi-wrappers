#!/usr/bin/env bash
# Renamed to setup.sh (standard wrapper interface). This stub forwards to it and will be removed
# in a later release; use scripts/pi/setup.sh.
echo "NOTE: setup-new-pi.sh is now setup.sh; running that." >&2
exec "$(dirname "$0")/setup.sh" "$@"
