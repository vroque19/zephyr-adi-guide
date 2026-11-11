# Using a different board

The [main guide](../README.md) uses the APARD32690. To use another ADI board you change two values:

| Value | Used by | Example |
| --- | --- | --- |
| Zephyr board name | `west build -b <board>` | `apard32690/max32690/m4` |
| OpenOCD target file (no `.cfg`) | `TARGET=` of [`scripts/flash-msdk.sh`](alternative-msdk.md) | `max32690` |

`TARGET=` is only for the MSDK script. For `west flash` (the ADI fork path) you only change the board name:
the runner derives the target file from the Zephyr board itself (see below).

## Boards checked

Only boards that were built here are listed. **No board was ever flashed**: no hardware was attached
for any row, so the last column is "no" for all of them.

| Zephyr board name | OpenOCD target cfg | Build verified | Flash verified on hardware |
| --- | --- | --- | --- |
| `apard32690/max32690/m4` | `max32690` | yes (`samples/hello_world`, Zephyr v4.5.0) | no (**untested**) |
| `max78000evkit/max78000/m4` | `max78000` | yes (`samples/hello_world`, Zephyr v4.5.0) | no (**untested**) |
| `max32655evkit/max32655/m4` | `max32655` | yes (`samples/hello_world`, Zephyr v4.5.0) | no (**untested**) |

### OpenOCD target file coverage

Which `target/<chip>.cfg` each OpenOCD has. Checked on one machine, no board attached, with
`openocd -s <scripts> -c 'puts [find target/<chip>.cfg]' -c shutdown` (Y = found, N = `Can't find target/<chip>.cfg`).

| Target cfg | MSDK (`Analog Devices 0.12.0-1.0.0-7`, 2023-09-27) | ADI fork (tag `0.12.0-1.4.0` build, 2026-03-11) | Zephyr SDK 1.0.1 (`0.12.0-01050-g91bd278a5`) | Zephyr SDK 0.17.4 (`0.12.0-01018-gb89d626c6`) |
| --- | --- | --- | --- | --- |
| `max32620`, `max32625` | Y | Y | Y | Y |
| `max32650` | Y | Y | N | N |
| `max32655` | Y | Y | N | N |
| `max32657`, `max32658` | N | Y | N | N |
| `max32660`, `max32670`, `max32672`, `max32675`, `max32680` | Y | Y | Y | N |
| `max32665` | Y | Y | N | N |
| `max32690` | Y | Y | Y | N |
| `max78000` | Y | Y | N | N |
| `max78002` | Y | Y | N | N |

No `max32666.cfg` exists in any of them (Zephyr maps MAX32666 boards to `max32665.cfg`, MAX32651 to `max32650.cfg`).
Zephyr SDK 1.0.1 has only the `max32620`, `max32625`, `max3263x`, `max32660`, `max32662`, `max32670`, `max32672`, `max32675`,
`max32680` and `max32690` files (plus `max32xxx_common.cfg`).

So for boards whose file your SDK's OpenOCD lacks (`max32655`, `max78000`, `max78002`, `max32650`, `max32665`, ...)
`west flash` with that OpenOCD cannot load the target: use the [ADI fork](../README.md#build-adi-openocd)
or the [MSDK alternative](alternative-msdk.md). For the `max32690` family with SDK 1.0.1 the file and the
`allow_low_pwr_dbg` command are both present, so the need for the fork was not shown (**untested with a board**).
See also [Troubleshooting](troubleshooting.md).

## How the two values are picked

Build for the other board by changing the board name (list them with
`west boards --format "{name}"`; a board with several cores shows them as `<board>/<soc>/<core>`):

```bash
west boards --format "{name} {qualifiers}" | grep -i max78000
west build -p always -b max78000evkit/max78000/m4 samples/hello_world
```

For `west flash`, the board directory under `<ZEPHYR_DIR>/boards/adi/<board>/` has a `board.cmake`.
The APARD32690's `board.cmake` contains:

```cmake
set(MAX32_TARGET_CFG "${CONFIG_SOC}.cfg")
set(MAX32_INTERFACE_CFG "cmsis-dap.cfg")
include(${ZEPHYR_BASE}/boards/common/openocd-adi-max32.boards.cmake)
```

and `max78000evkit`'s only includes `openocd-adi-max32.boards.cmake`, which defaults to
`${CONFIG_SOC}.cfg` and `cmsis-dap.cfg`. In other words the OpenOCD target file is the SoC name
(`max32690`, `max78000`) with `.cfg`, with a few exceptions written in that shared file (for example
`MAX32651` uses `max32650.cfg` and `MAX32666` uses `max32665.cfg`). That file also adds
`allow_low_pwr_dbg` to the OpenOCD command line for most Cortex-M MAX32 parts, which is why
OpenOCD must know that command ([Troubleshooting](troubleshooting.md)).

## A board that is not in the table

1. Find the board: `west boards --format "{name} {qualifiers}" | grep -i <name>`.
2. Read `<ZEPHYR_DIR>/boards/adi/<board>/board.cmake` and `<ZEPHYR_DIR>/boards/common/openocd-adi-max32.boards.cmake`
   to see which target file `west flash` will ask for.
3. Check that your OpenOCD has it (replace `<scripts>` with its scripts directory):

   ```bash
   openocd -s <scripts> -c 'puts [find target/<chip>.cfg]' -c shutdown
   ```

4. For the MSDK script, `ls ~/MaximSDK/Tools/OpenOCD/scripts/target | grep -i max` lists the names you can use as `TARGET=`.

Boards with a RISC-V core (for example `max78000fthr/max78000/rv32`) use a different debug interface in that
file; they were not built or checked here.
