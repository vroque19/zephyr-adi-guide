#!/usr/bin/env bash
# Flash a Zephyr hex file with the MSDK's OpenOCD (west flash cannot be used with it).
# Usage: TARGET=max32690 scripts/flash-msdk.sh [HEX_FILE]
#   TARGET     required. OpenOCD target config name without .cfg (e.g. max32690, max32655)
#   MSDK_DIR   MSDK install directory (default: $HOME/MaximSDK)
#   INTERFACE  OpenOCD interface config name without .cfg (default: cmsis-dap)
#   HEX_FILE   default: build/zephyr/zephyr.hex
set -euo pipefail

msdk_dir="${MSDK_DIR:-$HOME/MaximSDK}"
interface="${INTERFACE:-cmsis-dap}"
hex_file="${1:-build/zephyr/zephyr.hex}"
openocd="$msdk_dir/Tools/OpenOCD/bin/openocd"
scripts_dir="$msdk_dir/Tools/OpenOCD/scripts"

if [ -z "${TARGET:-}" ]; then
  echo "error: TARGET is not set. Example: TARGET=max32690 $0" >&2
  exit 1
fi

# TARGET and INTERFACE end up inside OpenOCD (Tcl) commands: allow plain names only.
valid_name='^[A-Za-z0-9_.-]+$'
if ! printf '%s\n' "$TARGET" | grep -Eq "$valid_name"; then
  echo "error: TARGET must be a plain name like max32690 (letters, digits, _ . -), got: $TARGET" >&2
  exit 1
fi
if ! printf '%s\n' "$interface" | grep -Eq "$valid_name"; then
  echo "error: INTERFACE must be a plain name like cmsis-dap (letters, digits, _ . -), got: $interface" >&2
  exit 1
fi

if [ ! -f "$hex_file" ]; then
  echo "error: hex file not found: $hex_file" >&2
  echo "Build first (west build ...) or pass the path to a .hex file." >&2
  exit 1
fi

if [ ! -x "$openocd" ]; then
  echo "error: $openocd is missing or not executable." >&2
  echo "Install the MSDK, or set MSDK_DIR to its install directory." >&2
  exit 1
fi

if [ ! -f "$scripts_dir/target/$TARGET.cfg" ]; then
  echo "error: $scripts_dir/target/$TARGET.cfg not found." >&2
  echo "Targets that look similar:" >&2
  { ls "$scripts_dir/target" 2>/dev/null | grep -i max || true; } | sed 's/^/  /' >&2
  exit 1
fi

if [ ! -f "$scripts_dir/interface/$interface.cfg" ]; then
  echo "error: $scripts_dir/interface/$interface.cfg not found." >&2
  echo "Some available interfaces:" >&2
  { ls "$scripts_dir/interface" 2>/dev/null | head -20 || true; } | sed 's/^/  /' >&2
  exit 1
fi

# The hex path goes through the environment so that OpenOCD's Tcl sees it as one word
# (spaces, $, [ ], ; and quotes in the path are not interpreted).
export FLASH_HEX="$hex_file"

exec "$openocd" -s "$scripts_dir" \
  -c "source [find interface/$interface.cfg]" \
  -c "source [find target/$TARGET.cfg]" \
  -c 'init' -c 'targets' -c 'reset init' \
  -c 'flash write_image erase $::env(FLASH_HEX)' \
  -c 'reset run' -c 'shutdown'
