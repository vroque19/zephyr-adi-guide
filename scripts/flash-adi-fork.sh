#!/usr/bin/env bash
# Flash with ADI's OpenOCD fork instead of the one bundled with the Zephyr SDK.
# Usage: scripts/flash-adi-fork.sh [west-flash-args...]
# Set OPENOCD_PREFIX if you installed the fork somewhere else (default: $HOME/.local).
set -eu

prefix="${OPENOCD_PREFIX:-$HOME/.local}"

if [ ! -x "$prefix/bin/openocd" ]; then
  echo "error: $prefix/bin/openocd is missing or not executable." >&2
  echo "Build and install the ADI OpenOCD fork first, or set OPENOCD_PREFIX to its install prefix." >&2
  exit 1
fi

if [ ! -d "$prefix/share/openocd/scripts" ]; then
  echo "error: $prefix/share/openocd/scripts is not a directory." >&2
  echo "The OpenOCD install looks incomplete. Run make install again, or set OPENOCD_PREFIX to the right prefix." >&2
  exit 1
fi

command -v west >/dev/null || { echo "error: west not found; activate the Zephyr virtual environment (source ~/zephyrproject/.venv/bin/activate)" >&2; exit 1; }

exec west flash --openocd "$prefix/bin/openocd" \
  --openocd-search "$prefix/share/openocd/scripts" "$@"
