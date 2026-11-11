# Troubleshooting

- [`west flash` fails with `FATAL ERROR: command exited with status 1`](#west-flash-fails-with-fatal-error-command-exited-with-status-1)
- [`Can't find target/<chip>.cfg`](#cant-find-targetchipcfg)
- [`Error: unable to find a matching CMSIS-DAP device`](#error-unable-to-find-a-matching-cmsis-dap-device)
- [`libncurses.so.5: cannot open shared object file`](#libncursesso5-cannot-open-shared-object-file-or-libtinfoso5)
- [Is my OpenOCD new enough?](#is-my-openocd-new-enough)

## `west flash` fails with `FATAL ERROR: command exited with status 1`

Symptom (paths shortened; `<SDK>` is your Zephyr SDK, `<ZEPHYR_DIR>` your Zephyr checkout):

```text
Open On-Chip Debugger 0.12.0-01050-g91bd278a5 (2026-03-25-02:24)
Licensed under GNU GPL v2
For bug reports, read
  http://openocd.org/doc/doxygen/bugs.html
FATAL ERROR: command exited with status 1: <SDK>/hosttools/sysroots/x86_64-pokysdk-linux/usr/bin/openocd -s <SDK>/hosttools/sysroots/x86_64-pokysdk-linux/usr/share/openocd/scripts --log_output <ZEPHYR_DIR>/build/openocd.log -c 'if { [info exists _ZEPHYR_BOARD_SERIAL] } { adapter serial $_ZEPHYR_BOARD_SERIAL }' -c 'source [find interface/cmsis-dap.cfg]' -c 'source [find target/max32655.cfg]' -c allow_low_pwr_dbg '-c init' '-c targets' -c 'reset init' -c 'flash write_image erase <ZEPHYR_DIR>/build/zephyr/zephyr.hex' -c 'reset run' -c shutdown
```

This message is only `west` reporting that OpenOCD exited with an error. It does not say why.
Find the reason first:

- If the command has `--log_output <file>`, read the end of that file (`tail build/openocd.log`).
- Otherwise OpenOCD's messages are printed just above the `FATAL ERROR` line. (On the machine used for this
  guide the default runner printed them there and created no `build/openocd.log`.)
- Or run the OpenOCD command that `west` printed by hand.

Then match the last `Error:` line:

1. `Error: unable to find a matching CMSIS-DAP device`: the board is not attached to WSL. This is the first thing to rule out.
   See [the next entry](#error-unable-to-find-a-matching-cmsis-dap-device).
2. `Can't find target/<chip>.cfg`: this OpenOCD has no file for your chip.
   See [`Can't find target/<chip>.cfg`](#cant-find-targetchipcfg).
3. An error about the command `allow_low_pwr_dbg` (it is on the printed command line): that OpenOCD does not have the command.
   The MSDK's OpenOCD is one that does not (see below).

What was checked here with no board attached, and where it was run (so that it ends at the missing adapter):

- `west flash` for the APARD32690 with the Zephyr SDK 1.0.1's own OpenOCD (`0.12.0-01050-g91bd278a5`) printed
  `Error: libusb initialization failed: Other error` and `Error: unable to find a matching CMSIS-DAP device`,
  then the `FATAL ERROR: command exited with status 1` line above (same shape as the example).
- The same with the ADI fork (`west flash --openocd ... --openocd-search ...`): `Error: unable to find a matching CMSIS-DAP device`,
  then the same `FATAL ERROR` line.
- For a MAX78000 board, the Zephyr SDK 1.0.1's OpenOCD printed `Can't find target/max78000.cfg` before `FATAL ERROR`.
- The MSDK's OpenOCD (`Analog Devices 0.12.0-1.0.0-7`) has no `allow_low_pwr_dbg` command; the ADI fork and the Zephyr SDK 1.0.1's OpenOCD have it.

**Untested with a board:** the author has not yet reproduced a failure of the bundled OpenOCD with a board attached,
so the claim is not that the SDK's OpenOCD cannot flash ADI boards. It was not tried.

Fix:

- Main path: build and use the [ADI OpenOCD fork](../README.md#build-adi-openocd) and [flash with it](../README.md#flash).
- Alternative: [flash with the MSDK's OpenOCD](alternative-msdk.md), which does not use `allow_low_pwr_dbg`.
- To check an OpenOCD before you try, see [Is my OpenOCD new enough?](#is-my-openocd-new-enough).

## `Can't find target/<chip>.cfg`

Example: `Can't find target/max32690.cfg`. This OpenOCD has no target file for that chip.

Checked here: the OpenOCD in Zephyr SDK 0.17.4 (`0.12.0-01018-gb89d626c6`) has only `max32620`, `max32625` and `max3263x`
target files and prints `Can't find target/max32690.cfg`. Zephyr SDK 1.0.1's OpenOCD has `max32690.cfg` but no `max32655.cfg` or `max78000.cfg`
(see [Boards](boards.md)). The MSDK's OpenOCD and the ADI fork have all three.

Fix: use an OpenOCD that has the file.

- Zephyr v4.5.0 needs Zephyr SDK 1.0 or newer anyway ([Install the Zephyr SDK](../README.md#4-install-the-zephyr-sdk)).
- For boards the SDK's OpenOCD does not have, use the [ADI fork](../README.md#build-adi-openocd) or the [MSDK](alternative-msdk.md).
- Make sure the OpenOCD you think is running is the one that runs: `which -a openocd` (see [Check which OpenOCD runs](../README.md#4-check-which-openocd-runs)).

## `Error: unable to find a matching CMSIS-DAP device`

OpenOCD found its files but no debug adapter. The board is almost always not attached to WSL.
On WSL you may also see `Error: libusb initialization failed: Other error` just before it; that goes with no USB device being visible.
Both were seen here with no board attached.

1. In WSL run `lsusb`. You should see the debugger (for example `ARM DAPLink CMSIS-DAP`). If not, the board is not attached.
2. On Windows run `usbipd list` and check that the board's `STATE` is `Attached`; if not, run
   `usbipd attach --wsl --busid <BUSID>` again. See [Connect your board to WSL](../README.md#connect-your-board-to-wsl).
3. The attachment is lost when you unplug the board, reboot, or restart WSL. Replug, or try another cable (some are charge-only) or port.
4. Use the board's debug USB port, not a power-only one.

If `lsusb` shows the debugger and the error remains, that is not covered here (a permission or adapter problem was not checked).

## `libncurses.so.5: cannot open shared object file` (or `libtinfo.so.5`)

Ubuntu 24.04 dropped `libncurses5`. Only the MSDK's `arm-none-eabi-gdb` needs it.
Zephyr's own gdb (`arm-zephyr-eabi-gdb`) does not, so you can skip this if you do not use MSDK gdb.

The fix is to install the Ubuntu 22.04 packages (**untested**, needs `sudo`):

```bash
cd "$(mktemp -d)"
BASE=http://security.ubuntu.com/ubuntu/pool/universe/n/ncurses
wget $BASE/libtinfo5_6.3-2ubuntu0.3_amd64.deb $BASE/libncurses5_6.3-2ubuntu0.3_amd64.deb
sudo apt install ./libtinfo5_6.3-2ubuntu0.3_amd64.deb ./libncurses5_6.3-2ubuntu0.3_amd64.deb
```

If the version in those file names stops resolving, browse the `BASE` URL for the
current `libtinfo5` and `libncurses5` `.deb` files.

## Is my OpenOCD new enough?

Two checks, neither needs a board. Replace `<openocd>` with the binary and `<scripts>` with its scripts directory
(for the Zephyr SDK: `<SDK>/hosttools/sysroots/x86_64-pokysdk-linux/usr/bin/openocd` and
`<SDK>/hosttools/sysroots/x86_64-pokysdk-linux/usr/share/openocd/scripts`; for the MSDK: `~/MaximSDK/Tools/OpenOCD/bin/openocd`
and `~/MaximSDK/Tools/OpenOCD/scripts`). Replace `<chip>` with your target (`max32690`, `max78000`, ...).

1. Does it have the target file? It prints the path, or `Can't find target/<chip>.cfg`:

   ```bash
   <openocd> -s <scripts> -c 'puts [find target/<chip>.cfg]' -c shutdown
   ```

2. Does it have the `allow_low_pwr_dbg` command that Zephyr's `west flash` uses? The command is defined by the target file,
   so load the interface and target first. It prints `1` if the command exists and `0` if not:

   ```bash
   <openocd> -s <scripts> -c 'source [find interface/cmsis-dap.cfg]' -c 'source [find target/<chip>.cfg]' \
     -c 'puts "allow_low_pwr_dbg count: [llength [info commands allow_low_pwr_dbg]]"' -c shutdown
   ```

Results here, for `max32690` (after the `Error: unable to find a matching CMSIS-DAP device` line that appears with no board):

| OpenOCD | `find target/max32690.cfg` | `allow_low_pwr_dbg count` |
| --- | --- | --- |
| MSDK `Analog Devices 0.12.0-1.0.0-7` | found | 0 |
| ADI fork `0.12.0-1.4.0` build | found | 1 |
| Zephyr SDK 1.0.1 | found | 1 |
| Zephyr SDK 0.17.4 | `Can't find target/max32690.cfg` | not run |

Version drift: the Zephyr SDK and the upstream/ADI OpenOCD change over time, and the table above is a snapshot.
If a newer Zephyr SDK ships an OpenOCD that passes both checks for your chip, the default `west flash` may work without
the fork; try it with your board attached and report what happens. Zephyr's own `west flash` command line (printed on failure) shows
which target file and commands it needs, and
`<ZEPHYR_DIR>/boards/common/openocd-adi-max32.boards.cmake` is where they are set.
Passing both checks only shows that the file and command exist, not that flashing works (**untested with a board**).
