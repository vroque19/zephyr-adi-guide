#!/usr/bin/env bash
# Flash with ADI's OpenOCD fork instead of the one bundled with the Zephyr SDK.
# Usage: scripts/flash-adi-fork.sh [west-flash-args...]
# Set OPENOCD_PREFIX if you installed the fork somewhere else (default: /usr/local).
set -eu

prefix="${OPENOCD_PREFIX:-/usr/local}"

if [ ! -x "$prefix/bin/openocd" ]; then
  echo "error: $prefix/bin/openocd is missing or not executable." >&2
  echo "Build and install the ADI OpenOCD fork first, or set OPENOCD_PREFIX to its install prefix." >&2
  exit 1
fi

exec west flash --openocd "$prefix/bin/openocd" \
  --openocd-search "$prefix/share/openocd/scripts" "$@"
