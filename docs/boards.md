# Using a different board

The [main guide](../README.md) uses the APARD32690. To use another ADI board you change two values:

| Value | Used by | Example |
| --- | --- | --- |
| Zephyr board name | `west build -b <board>` | `apard32690/max32690/m4` |
| OpenOCD target file (no `.cfg`) | `TARGET=` of [`scripts/flash-msdk.sh`](alternative-msdk.md) | `max32690` |

For the ADI fork path (`west flash`) you only change the board name. Zephyr's board files pick the
OpenOCD target file for you (see below).

## Boards checked

Only boards that were built here are listed. **No board was ever flashed**: no hardware was attached
for any row, so the last column is "no" for all of them.

| Zephyr board name | OpenOCD target cfg | Build verified | Flash verified on hardware |
| --- | --- | --- | --- |
| `apard32690/max32690/m4` | `max32690` | yes (`samples/hello_world`, Zephyr v4.5.0) | no (**untested**) |
| `max78000evkit/max78000/m4` | `max78000` | yes (`samples/hello_world`, Zephyr v4.5.0) | no (**untested**) |

Where the target file exists (checked with `find target/<chip>.cfg` and no board attached):

| Target cfg | MSDK OpenOCD | ADI fork `0.12.0-1.4.0` build | Zephyr SDK 1.0.1 OpenOCD |
| --- | --- | --- | --- |
| `max32690.cfg` | found | found | found |
| `max78000.cfg` | found | found | **not found** (`Can't find target/max78000.cfg`) |

So for a MAX78000 board the OpenOCD that comes with Zephyr SDK 1.0.1 cannot even load the target file:
use the [ADI fork](../README.md#build-adi-openocd) or the [MSDK alternative](alternative-msdk.md).
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
