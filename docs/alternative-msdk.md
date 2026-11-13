# Alternative: flash with the MSDK's OpenOCD

The [main guide](../README.md) flashes with ADI's OpenOCD fork through `west flash`.
This page is the other route: use the OpenOCD that ships with the MSDK and a small script.

## When to use this path

- You already have the MSDK and do not want to build the fork.
- Your board's target file is in the MSDK's OpenOCD (check below).

If neither applies, stay with the fork.

## Prerequisites

Everything in the [README](../README.md) up to and including [Build hello_world](../README.md#5-build-hello_world),
plus the Maxim Microcontrollers SDK (MSDK). The MSDK is needed only for this alternative path and for the MSDK's `arm-none-eabi-gdb`.
Install it from the [MSDK installation instructions](https://analogdevicesinc.github.io/msdk/USERGUIDE/#installation),
accepting the default location (`~/MaximSDK`). The MSDK tested had GNU Arm toolchain 10.3-2021.10 and OpenOCD "Analog Devices 0.12.0-1.0.0-7". Check it:

```bash
ls ~/MaximSDK/Tools/OpenOCD/bin/openocd
```

The board must be attached as in [Connect your board to WSL](../README.md#connect-your-board-to-wsl).

You also need the helper script `scripts/flash-msdk.sh`. Get it as in
[Optional helper scripts](../README.md#optional-helper-scripts) (clone this repository and set `GUIDE_DIR`).

## Flash with the script

Build first, from `~/zephyrproject/zephyr` with the venv active:

```bash
west build -p always -b apard32690/max32690/m4 samples/hello_world
```

Then flash. `TARGET` is required: it is the OpenOCD target file name without `.cfg`.

```bash
TARGET=max32690 "$GUIDE_DIR/scripts/flash-msdk.sh"
```

To use another board, change `TARGET` (and build for that board). Two examples:

```bash
TARGET=max32690 "$GUIDE_DIR/scripts/flash-msdk.sh"
TARGET=max32655 "$GUIDE_DIR/scripts/flash-msdk.sh"
```

The MSDK has two script trees and the script accepts a target from either one (details in
[boards](boards.md#openocd-target-file-coverage)). List the names from both trees:

```bash
ls -1 ~/MaximSDK/Tools/OpenOCD/scripts/target | grep '^max.*\.cfg$'
ls -1 ~/MaximSDK/Tools/OpenOCD/share/openocd/scripts/target | grep '^max.*\.cfg$'
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
the full path and `-s`, the MSDK's binary only reads the MSDK's own scripts. See below for what ran without a board.

## Why `west flash` can't be used

`west flash` (Zephyr's openocd runner) sends the OpenOCD command `allow_low_pwr_dbg`.
The MSDK's OpenOCD (`Analog Devices 0.12.0-1.0.0-7`) does not have that command, so `west flash` is expected not to work with it (inferred: the command is absent in that binary; ran without a board).
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

The Zephyr SDK 0.17.4 `openocd` has no `target/max32690.cfg` (ran without a board on one machine; not re-run for this page), so
`Can't find target/max32690.cfg` is the error you get if that binary is the one that runs. `which -a openocd` only shows
which binaries your `PATH` finds and in what order. Some older instructions fix that error by deleting the system
`openocd` and its scripts and putting the MSDK's first on `PATH`. That is not needed with `scripts/flash-msdk.sh`.
What ran without a board:

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
  arguments against a stand-in `openocd` (a test script, not the real tool), for `max32690` and `max32655`.
- The script against the real MSDK `openocd` with `TARGET=max32690` and a dummy hex file: it loaded the target file and
  stopped at `unable to find a matching CMSIS-DAP device`, as expected with no board.
- **Probed with a board** (read-only, `init` and `targets` only, MAX78000-class board attached): the MSDK's `openocd` with the MSDK's `max78000.cfg` and `max32690.cfg`
  connected to the probe and a Cortex-M4 (see [Probed with a board](boards.md#probed-with-a-board)).
- **Flashed** (a write succeeded): `TARGET=max78000 scripts/flash-msdk.sh <build>/zephyr/zephyr.hex` wrote to a MAX78000FTHR with the MSDK's OpenOCD (`wrote 24576 bytes ... in 1.02s (23.6 KiB/s)`, `shutdown command invoked`). One board, one sample; running was not re-confirmed over serial for this script. The same script also wrote from a clean container (see the [test log](test-log.md#clean-container-test-ubuntu-2404)).
  `west flash` with the MSDK's OpenOCD was not run; it is still expected not to work (inferred, see above).
- **Untested:** other boards with this script, and `INTERFACE` values other than `cmsis-dap` on real hardware.
