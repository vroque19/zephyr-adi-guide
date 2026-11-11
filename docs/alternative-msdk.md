# Alternative: flash with the MSDK's OpenOCD

The [main guide](../README.md) flashes with ADI's OpenOCD fork through `west flash`.
This page is the other route: use the OpenOCD that ships with the MSDK and a small script.

## When to use this path

- You already have the MSDK and do not want to build the fork.
- Your board's target file is in the MSDK's OpenOCD (check below).

If neither applies, stay with the fork.

## Prerequisites

Everything in the [README](../README.md) up to and including [Build hello_world](../README.md#5-build-hello_world),
plus the [MSDK](../README.md#2-maxim-microcontrollers-sdk-msdk). Check it:

```bash
ls ~/MaximSDK/Tools/OpenOCD/bin/openocd
```

The board must be attached as in [Connect your board to WSL](../README.md#connect-your-board-to-wsl).

## Flash with the script

Build first, from `~/zephyrproject/zephyr` with the venv active:

```bash
west build -p always -b apard32690/max32690/m4 samples/hello_world
```

Then flash. `TARGET` is required: it is the OpenOCD target file name without `.cfg`.

```bash
TARGET=max32690 ~/path/to/zephyr-adi-guide/scripts/flash-msdk.sh
```

To use another board, change `TARGET` (and build for that board). Two examples:

```bash
TARGET=max32690 ~/path/to/zephyr-adi-guide/scripts/flash-msdk.sh
TARGET=max32655 ~/path/to/zephyr-adi-guide/scripts/flash-msdk.sh
```

List the targets your MSDK knows:

```bash
ls ~/MaximSDK/Tools/OpenOCD/scripts/target | grep -i max
```

Optional settings:

| Variable | Default | Meaning |
| --- | --- | --- |
| `MSDK_DIR` | `$HOME/MaximSDK` | where the MSDK is installed |
| `INTERFACE` | `cmsis-dap` | OpenOCD interface file, without `.cfg` |

The hex file defaults to `build/zephyr/zephyr.hex`. Pass another path as the only argument.
The script exits with a message on stderr if `TARGET` is unset, the hex file is missing,
`$MSDK_DIR/Tools/OpenOCD/bin/openocd` is missing, or the target or interface file does not exist.
`TARGET` and `INTERFACE` must be plain names (letters, digits, `_`, `.`, `-`). The hex path may contain spaces or other
characters: it is passed to OpenOCD through an environment variable, so OpenOCD reads it as one word.

It runs the MSDK's `openocd` by full path with `-s "$MSDK_DIR/Tools/OpenOCD/scripts"` and the same
steps as Zephyr's board file: `init`, `targets`, `reset init`, `flash write_image erase <hex>`, `reset run`, `shutdown`.

You do not need to remove or replace any other `openocd` on your system: because the script passes
the full path and `-s`, the MSDK's binary only reads the MSDK's own scripts. See below for what was checked.

## Why `west flash` can't be used

`west flash` (Zephyr's openocd runner) sends the OpenOCD command `allow_low_pwr_dbg`.
The MSDK's OpenOCD (`Analog Devices 0.12.0-1.0.0-7`) does not have that command, so `west flash` cannot drive it.
That is why the script writes the hex file directly instead. The ADI fork does have the command, which is why
the main guide can use `west flash`.

## Checking which openocd runs

```bash
which -a openocd
openocd --version
~/MaximSDK/Tools/OpenOCD/bin/openocd --version
```

The MSDK's prints `Open On-Chip Debugger (Analog Devices 0.12.0-1.0.0-7)  OpenOCD 0.12.0 (2023-09-27-07:53)`.

`~/MaximSDK/Tools/OpenOCD/openocd` is a symlink to `~/MaximSDK/Tools/OpenOCD/bin/openocd` (checked with `ls -l`), so both are the same binary.
The script uses the `bin/` path.

The Zephyr SDK 0.17.4 `openocd` has no `target/max32690.cfg` (found in an independent check, not reproduced in this task), so
`Can't find target/max32690.cfg` is the error you get if that binary is the one that runs. `which -a openocd` only shows
which binaries your `PATH` finds and in what order. The notes this guide started from fixed that error by deleting the system
`openocd` and its scripts and putting the MSDK's first on `PATH`. That is not needed with `scripts/flash-msdk.sh`.
What was checked (no board needed):

```bash
~/MaximSDK/Tools/OpenOCD/bin/openocd -s ~/MaximSDK/Tools/OpenOCD/scripts \
  -c 'puts [find target/max32690.cfg]' \
  -c 'source [find interface/cmsis-dap.cfg]' -c 'source [find target/max32690.cfg]' \
  -c init -c shutdown
```

It printed `~/MaximSDK/Tools/OpenOCD/scripts/target/max32690.cfg` (inside the MSDK) and then stopped at
`unable to find a matching CMSIS-DAP device`, so the file was found and loaded (on WSL, `Error: libusb initialization failed: Other error`
may come first; that is expected with no USB device). Without the `interface/cmsis-dap.cfg` line `init` has no adapter to look for
and that message does not appear. Run by full path, with or without `-s`,
this binary resolves its scripts under `~/MaximSDK/Tools/OpenOCD`, not under `/usr` or `/usr/local`.
Only plain `openocd` from `PATH` is affected by what else is installed.

If you prefer to run `openocd` by hand, put the MSDK first on `PATH` for that shell instead of deleting anything:

```bash
export PATH="$HOME/MaximSDK/Tools/OpenOCD/bin:$PATH"
which openocd
```

## What was tested

- The script's error paths (unset `TARGET`, missing hex, missing `openocd`, unknown target), and its exact `openocd`
  arguments against a stub, for `max32690` and `max32655`.
- The script against the real MSDK `openocd` with `TARGET=max32690` and a dummy hex file: it loaded the target file and
  stopped at `unable to find a matching CMSIS-DAP device`, as expected with no board.
- **Untested:** flashing a real board with this script, and `INTERFACE` values other than `cmsis-dap` on real hardware.
