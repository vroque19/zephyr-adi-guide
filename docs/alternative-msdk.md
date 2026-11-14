# Alternative: flash with the MSDK's OpenOCD

The [main guide](../README.md) builds ADI's OpenOCD fork and flashes with `west flash`.
This page is the other route: use the OpenOCD that ships with the Analog Devices MSDK and a small script.
Use it if you already have the MSDK and do not want to build the fork.

## Prerequisites

- The README steps up to and including building `hello_world` (steps 1 to 4).
- The MSDK, installed from the [MSDK instructions](https://analogdevicesinc.github.io/msdk/USERGUIDE/#installation) into the default `~/MaximSDK`.
  The MSDK is needed only for this path and for its `arm-none-eabi-gdb`.

```bash
ls ~/MaximSDK/Tools/OpenOCD/bin/openocd
```

- This repository, for the script:

```bash
git clone https://github.com/vroque19/zephyr-adi-guide.git ~/zephyr-adi-guide
export GUIDE_DIR="$HOME/zephyr-adi-guide"
```

## Flash

Build for your board, then flash. `TARGET` is required: the OpenOCD target file name without `.cfg` (see [boards](boards.md)).

```bash
cd ~/zephyrproject/zephyr
west build -p always -b max78000fthr/max78000/m4 samples/hello_world
TARGET=max78000 "$GUIDE_DIR/scripts/flash-msdk.sh"
```

Another board only changes the two values, for example `-b apard32690/max32690/m4` and `TARGET=max32690`.
To list the target names the MSDK has, run `ls ~/MaximSDK/Tools/OpenOCD/share/openocd/scripts/target | grep '^max'` (the MSDK has a second tree, `Tools/OpenOCD/scripts`; the script accepts names from either).

Options:

| Variable | Default | Meaning |
| --- | --- | --- |
| `MSDK_DIR` | `$HOME/MaximSDK` | where the MSDK is installed |
| `INTERFACE` | `cmsis-dap` | OpenOCD interface file, without `.cfg` |

The hex file defaults to `build/zephyr/zephyr.hex`; pass another path as the only argument.
The script stops with a message if `TARGET` is unset, the hex file or the MSDK's `openocd` is missing, or the target file does not exist.

It runs the MSDK's OpenOCD by full path with the same steps as Zephyr's board file: `init`, `targets`, `reset init`, `flash write_image erase <hex>`, `reset run`, `shutdown`.
You do not need to delete or move any other `openocd`: the MSDK's binary only reads the MSDK's own scripts.

## Why not `west flash`?

`west flash` sends the OpenOCD command `allow_low_pwr_dbg`, which the MSDK's OpenOCD (`Analog Devices 0.12.0-1.0.0-7`) does not have.
So the script writes the hex file directly. This was not tried with `west flash`.

## Check which `openocd` runs

```bash
which -a openocd
~/MaximSDK/Tools/OpenOCD/bin/openocd --version
```

The MSDK's prints `(Analog Devices 0.12.0-1.0.0-7)`. If you run `openocd` by hand, put the MSDK first on `PATH` for that shell instead of deleting anything:

```bash
export PATH="$HOME/MaximSDK/Tools/OpenOCD/bin:$PATH"
```
