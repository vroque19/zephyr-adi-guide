# Using a different board

Change the Zephyr board name in `west build -b <board>`. `west flash` works out the OpenOCD target file from the board itself.
Only the [MSDK script](alternative-msdk.md) needs a `TARGET` value (the target file name without `.cfg`).

## Boards flashed so far

| Zephyr board name | OpenOCD target | How it was flashed |
| --- | --- | --- |
| `max78000fthr/max78000/m4` | `max78000` | The ADI fork with `west flash --openocd ...` (maintainer). The MSDK script also worked. |
| `apard32690/max32690/m4` | `max32690` | Plain `west flash`, using the Zephyr SDK's OpenOCD (user report). The ADI fork at `0.12.0-1.4.0` failed: [troubleshooting](troubleshooting.md#invalid-command-name-init_qspi-on-the-max32690-adi-fork-0120-140). |

Other ADI boards should work the same way but have not been flashed.

## Which OpenOCD has your chip?

Y means the OpenOCD has `target/<chip>.cfg`, N means `Can't find target/<chip>.cfg`.

| Target | MSDK | ADI fork | Zephyr SDK 1.0.1 | Zephyr SDK 0.17.4 |
| --- | --- | --- | --- | --- |
| `max32620`, `max32625` | Y | Y | Y | Y |
| `max32650`, `max32655`, `max32665` | Y | Y | N | N |
| `max32657`, `max32658` | N | Y | N | N |
| `max32660`, `max32662`, `max32670`, `max32672`, `max32675`, `max32680` | Y | Y | Y | N |
| `max32690` | Y | Y | Y | N |
| `max78000`, `max78002` | Y | Y | N | N |

If your SDK has your chip (Y), plain `west flash` can work. If not, build [ADI's fork](../README.md#5-build-adis-openocd).
Zephyr maps `MAX32651` boards to `max32650.cfg` and `MAX32666` boards to `max32665.cfg`.

## Find the right values for a board

List the boards and build:

```bash
cd ~/zephyrproject/zephyr
west boards --format "{name} {qualifiers}" | grep -i max78000
west build -p always -b max78000evkit/max78000/m4 samples/hello_world
```

The target file is normally the SoC name plus `.cfg`. To see what `west flash` will ask for, read
`<ZEPHYR_DIR>/boards/adi/<board>/board.cmake` and `<ZEPHYR_DIR>/boards/common/openocd-adi-max32.boards.cmake`
(`<ZEPHYR_DIR>` is `~/zephyrproject/zephyr`). Then check that your OpenOCD has the file:

```bash
openocd -s <scripts-dir> -c 'puts [find target/<chip>.cfg]' -c shutdown
```

The shared board file also sends `allow_low_pwr_dbg` to OpenOCD, which the MSDK's OpenOCD does not know. That is why the MSDK needs [its own flash script](alternative-msdk.md).

Boards with a RISC-V core (for example `max78000fthr/max78000/rv32`) use a different debug setup and were not tried.
