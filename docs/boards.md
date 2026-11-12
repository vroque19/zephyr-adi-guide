# Using a different board

The [main guide](../README.md) uses the MAX78000FTHR (the only board flashed). To use another ADI board you change the Zephyr board name. The MSDK script needs one more value:

| Value | Used by | Example |
| --- | --- | --- |
| Zephyr board name | `west build -b <board>` | `max78000fthr/max78000/m4` |
| OpenOCD target file (no `.cfg`) | `TARGET=` of [`scripts/flash-msdk.sh`](alternative-msdk.md) | `max78000` |

`TARGET=` is only for the MSDK script. For `west flash` (the ADI fork path) you only change the board name
(`west build -b`): the runner (the part of `west flash` that drives OpenOCD) derives the target file from the Zephyr board itself (see below).

## Boards built

Only boards that were built here are listed. **Only one board was flashed, the MAX78000FTHR** (**flashed**: OpenOCD printed `wrote N bytes`; one board, one sample). The program was confirmed running over serial after the `west flash --openocd` run with the pinned fork, followed by `reset run`. The other rows are "no".
That board was first probed read-only (see [Probed with a board](#probed-with-a-board)). `<ZEPHYR_DIR>` is `~/zephyrproject/zephyr`.

| Zephyr board name | OpenOCD target cfg (config file) | Built | Flashed on hardware |
| --- | --- | --- | --- |
| `apard32690/max32690/m4` | `max32690` | yes (`samples/hello_world`, Zephyr v4.5.0) | no (**untested**) |
| `max78000evkit/max78000/m4` | `max78000` | yes (`samples/hello_world`, Zephyr v4.5.0) | no (**untested**) |
| `max32655evkit/max32655/m4` | `max32655` | yes (`samples/hello_world`, Zephyr v4.5.0) | no (**untested**) |
| `max78000fthr/max78000/m4` | `max78000` | yes (`samples/hello_world`, Zephyr v4.5.0) | yes (**flashed** with the pinned fork `west flash`, confirmed running over serial; `scripts/flash-adi-fork.sh` and `scripts/flash-msdk.sh` also wrote, running not re-confirmed) |

### Probed with a board

OpenOCD was run read-only against one attached board, as a normal user: `-c 'source [find interface/cmsis-dap.cfg]' -c 'source [find target/<chip>.cfg]' -c init -c targets -c shutdown`.
These probes flashed, wrote and reset nothing. The board was a MAX78000-class Cortex-M4 board with an on-board DAPLink probe (SWD `DPIDR 0x2ba01477`).
A cell says `connected` when OpenOCD printed `Examination succeed` or a target table, or `Can't find` when the cfg is missing.

| OpenOCD | `max78000.cfg` | `max32690.cfg` |
| --- | --- | --- |
| ADI fork, tag `0.12.0-1.4.0` (the README's pinned build, temporary prefix) | connected (`Examination succeed`; an earlier build of the tag, see the [test log](test-log.md)) | not run |
| ADI fork (build at `/usr/local/bin/openocd`, 2026-03-11) | connected | connected (config-only check; board is MAX78000-class) |
| Zephyr SDK 1.0.1 (`0.12.0-01050-g91bd278a5`) | `Can't find target/max78000.cfg` | connected (config-only check; board is MAX78000-class; target state `running`) |
| MSDK (`Analog Devices 0.12.0-1.0.0-7`) | connected | connected (config-only check; board is MAX78000-class) |

What this shows and does not show:

- The attached board is a MAX78000-class board, so `max78000.cfg` is the matching file. `max32690.cfg` connecting on it only shows that the OpenOCD can talk to this probe
  and a Cortex-M4 with that cfg. It does **not** show that MAX32690 boards flash or connect.
- The fork builds printed target state `unknown` while the SDK and MSDK printed `running`; this was not investigated.
- Zephyr SDK 1.0.1's OpenOCD fails on `max78000.cfg` with the board attached, exactly as without one: the file is missing.
- `allow_low_pwr_dbg` (checked host-only, after loading the cfg, without `init`): present in the fork build and Zephyr SDK 1.0.1, absent in the MSDK.
- The probes above themselves wrote nothing. Afterwards the same board was flashed: only the pinned fork (temporary prefix) and the MSDK script flashed it; the `/usr/local` fork build was
  not used for flashing, and Zephyr SDK 1.0.1 could not flash a MAX78000 (missing cfg). Flashing the other boards stays **untested**.

### OpenOCD target file coverage

Which `target/<chip>.cfg` each OpenOCD has. Ran on one machine without a board, with
`openocd -s <scripts> -c 'puts [find target/<chip>.cfg]' -c shutdown` (Y = found, N = `Can't find target/<chip>.cfg`).
The fork column was measured on a fork build installed in `/usr/local` on the test machine, not necessarily tag `0.12.0-1.4.0` from the README. The build of
tag `0.12.0-1.4.0` was checked separately for those three files only: `max32690.cfg`, `max32655.cfg` and `max78000.cfg` are present.

| Target cfg | MSDK (`Analog Devices 0.12.0-1.0.0-7`, 2023-09-27) | ADI fork (build at `/usr/local/bin/openocd`, 2026-03-11, no tag in its version string) | Zephyr SDK 1.0.1 (`0.12.0-01050-g91bd278a5`) | Zephyr SDK 0.17.4 (`0.12.0-01018-gb89d626c6`) |
| --- | --- | --- | --- | --- |
| `max32620`, `max32625` | Y | Y | Y | Y |
| `max32650` | Y | Y | N | N |
| `max32655` | Y | Y | N | N |
| `max32657`, `max32658` | N | Y | N | N |
| `max32660`, `max32662`, `max32670`, `max32672`, `max32675`, `max32680` | Y | Y | Y | N |
| `max32665` | Y | Y | N | N |
| `max32690` | Y | Y | Y | N |
| `max78000` | Y | Y | N | N |
| `max78002` | Y | Y | N | N |

No `max32666.cfg` exists in any of them (Zephyr maps MAX32666 boards to `max32665.cfg`, MAX32651 to `max32650.cfg`).
Zephyr SDK 1.0.1 has only the `max32620`, `max32625`, `max3263x`, `max32660`, `max32662`, `max32670`, `max32672`, `max32675`,
`max32680` and `max32690` files (plus `max32xxx_common.cfg`).

So for boards whose file your SDK's OpenOCD lacks (`max32650`, `max32655`, `max32657`, `max32658`, `max32665`, `max78000`, `max78002`; those checks ran without a board)
`west flash` with that OpenOCD cannot load the target (the same kind of failure as in [Troubleshooting](troubleshooting.md); to confirm your case, read the log). Use the [ADI fork](../README.md#build-adi-openocd)
or the [MSDK alternative](alternative-msdk.md) (the MSDK also lacks `max32657` and `max32658`: the fork only). For the `max32690` family with SDK 1.0.1 the file and the
`allow_low_pwr_dbg` command are both present, so the need for the fork was not shown (**untested with a board**).
Which Zephyr boards need which cfg (from the `select SOC_...` lines in `<ZEPHYR_DIR>/boards/adi/*/Kconfig.*` and the shared
`openocd-adi-max32.boards.cmake`) is in the
[affected boards table](troubleshooting.md#west-flash-fails-with-fatal-error-command-exited-with-status-1).

The MSDK's OpenOCD has two script trees, `Tools/OpenOCD/scripts` and `Tools/OpenOCD/share/openocd/scripts`. By `ls`, `max32620`,
`max32625` and `max3263x` exist only in the second (and `find` resolves them); the other MSDK cfgs in the matrix (`max32650`, `max32655`,
`max32660`, `max32665`, `max32670`, `max32672`, `max32675`, `max32680`, `max32690`, `max78000`, `max78002`) are in both. `max32657`
and `max32658` are in neither. `scripts/flash-msdk.sh` passes `-s Tools/OpenOCD/scripts`, but OpenOCD also keeps its built-in search path (`bin/../share/openocd/scripts`),
so `find target/max32620.cfg`, `max32625.cfg` and `max3263x.cfg` still resolve to the second tree when run that way (ran without a board). Only a plain
`ls .../scripts/target` under-lists the usable names. The script's own existence check accepts a target (or interface) found in either tree, so `TARGET=max32625` reaches OpenOCD
(ran with a dummy hex file: it ends at `unable to find a matching CMSIS-DAP device`).

## How the values are picked

Build for the other board by changing the board name (list them with
`west boards --format "{name}"`; a board with several cores shows them as `<board>/<soc>/<core>`):

```bash
cd ~/zephyrproject/zephyr
west boards --format "{name} {qualifiers}" | grep -i max78000
west build -p always -b max78000evkit/max78000/m4 samples/hello_world -d build
```

For `west flash`, the board directory under `<ZEPHYR_DIR>/boards/adi/<board>/` has a `board.cmake` (Zephyr's per-board flash settings).
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

4. For the MSDK script, list the OpenOCD target names of each tree:

   ```bash
   ls -1 ~/MaximSDK/Tools/OpenOCD/scripts/target | grep '^max.*\.cfg$'
   ls -1 ~/MaximSDK/Tools/OpenOCD/share/openocd/scripts/target | grep '^max.*\.cfg$'
   ```

   Or ask OpenOCD directly: `~/MaximSDK/Tools/OpenOCD/bin/openocd -c 'puts [find target/<chip>.cfg]' -c shutdown`.
   The script accepts names from either tree (see above).

Boards with a RISC-V core (for example `max78000fthr/max78000/rv32`) use a different debug interface in that
file; they were not built or run here.
