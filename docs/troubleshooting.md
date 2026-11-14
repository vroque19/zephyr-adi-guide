# Troubleshooting

- [`west zephyr-export` fails with `ModuleNotFoundError: No module named 'jsonschema'`](#west-zephyr-export-fails-with-modulenotfounderror-no-module-named-jsonschema)
- [Serial output is garbage](#serial-output-is-garbage)
- [`server certificate verification failed` behind a corporate proxy](#server-certificate-verification-failed-behind-a-corporate-proxy)
- [`west flash` fails with `FATAL ERROR: command exited with status 1`](#west-flash-fails-with-fatal-error-command-exited-with-status-1)
- [`invalid command name "init_qspi"` on the MAX32690 (ADI fork 0.12.0-1.4.0)](#invalid-command-name-init_qspi-on-the-max32690-adi-fork-0120-140)
- [Flash says `wrote N bytes` but nothing runs](#flash-says-wrote-n-bytes-but-nothing-runs)
- [`Can't find target/<chip>.cfg`](#cant-find-targetchipcfg)
- [`Error: unable to find a matching CMSIS-DAP device`](#error-unable-to-find-a-matching-cmsis-dap-device)
- [Access denied / permission error opening the probe](#access-denied--permission-error-opening-the-probe)
- [`libncurses.so.5: cannot open shared object file`](#libncursesso5-cannot-open-shared-object-file-or-libtinfoso5)
- [Is my OpenOCD new enough?](#is-my-openocd-new-enough)

## `west zephyr-export` fails with `ModuleNotFoundError: No module named 'jsonschema'`

Seen on a fresh Ubuntu 24.04 (clean container) when `west zephyr-export` ran before `west packages pip --install`. The traceback ends with
`ModuleNotFoundError: No module named 'jsonschema'`, then west prints `AttributeError: 'NoneType' object has no attribute 'err'`. If you chain commands with `&&`, the first line scrolls away.
The cause is that west loads Zephyr's extension commands, which import Python packages that are not installed yet.

Fix: with the venv active, run `west packages pip --install`, then `west zephyr-export`.

## Serial output is garbage

Symptom: `cat /dev/ttyACM0` after `stty -F /dev/ttyACM0 115200 raw -echo` prints random bytes (like `dc d9 98 64 fe ...`) instead of `*** Booting Zephyr OS build v4.5.0 ***`,
even though `stty -a` reports 115200 baud. Observed on a MAX78000FTHR, from a container and from the host, in three attempts.

Fix (observed to work): force a real baud change first, then reset the board:

```bash
stty -F /dev/ttyACM0 9600 raw -echo; stty -F /dev/ttyACM0 115200 raw -echo; cat /dev/ttyACM0
```

The expected lines are the same as in the [Quick start](../README.md#quick-start). The cause is not confirmed: a guess is that `stty` does nothing when the driver already thinks the port is at 115200,
so the probe's UART bridge keeps another baud rate.

## `server certificate verification failed` behind a corporate proxy

Symptom: `git clone --recurse-submodules` of the OpenOCD fork fails with `server certificate verification failed` (the `libjaylink` submodule is cloned from `https://gitlab.zapb.de`), or
`wget` fails with `ERROR: cannot verify security.ubuntu.com's certificate ... Self-signed certificate encountered` (for example in the [libncurses entry](#libncursesso5-cannot-open-shared-object-file-or-libtinfoso5)).
Observed only inside a Docker container behind a TLS-inspecting corporate proxy; the same URLs worked from the WSL distribution.

Fix (**untested**): ask your IT department for your organisation's root CA certificate, copy it to `/usr/local/share/ca-certificates/<name>.crt` and run `sudo update-ca-certificates`.
Do not disable certificate verification (`wget --no-check-certificate`, `GIT_SSL_NO_VERIFY`): that removes the protection the download relies on.
Workaround used in the test: clone or download on a machine that is not intercepted and copy the files in.

## `west flash` fails with `FATAL ERROR: command exited with status 1`

> **MAX78000FTHR, max78000, max32655, max78002, max32650, max32665, max32657 or max32658 boards: do this.**
> Build the [ADI OpenOCD fork](../README.md#build-adi-openocd), set `OPENOCD_PREFIX` to its install prefix, then run from `<ZEPHYR_DIR>`:
> `west flash --openocd "$OPENOCD_PREFIX/bin/openocd" --openocd-search "$OPENOCD_PREFIX/share/openocd/scripts"` (flashed on a MAX78000FTHR; the other chips are untested).

Symptom (paths shortened; `<SDK>` is your Zephyr SDK, `<ZEPHYR_DIR>` your Zephyr checkout, `~/zephyrproject/zephyr` in the guide):

```text
runners.openocd: INFO: OpenOCD log file: <ZEPHYR_DIR>/build/openocd.log
runners.openocd: INFO: Flashing file: <ZEPHYR_DIR>/build/zephyr/zephyr.hex
Open On-Chip Debugger 0.12.0-01050-g91bd278a5 (2026-03-25-02:24)
Licensed under GNU GPL v2
For bug reports, read
  http://openocd.org/doc/doxygen/bugs.html
FATAL ERROR: command exited with status 1: <SDK>/hosttools/sysroots/x86_64-pokysdk-linux/usr/bin/openocd -s <SDK>/hosttools/sysroots/x86_64-pokysdk-linux/usr/share/openocd/scripts --log_output <ZEPHYR_DIR>/build/openocd.log -c 'if { [info exists _ZEPHYR_BOARD_SERIAL] } { adapter serial $_ZEPHYR_BOARD_SERIAL }' -c 'source [find interface/cmsis-dap.cfg]' -c 'source [find target/max32655.cfg]' -c allow_low_pwr_dbg '-c init' '-c targets' -c 'reset init' -c 'flash write_image erase <ZEPHYR_DIR>/build/zephyr/zephyr.hex' -c 'reset run' -c shutdown
```

This message is only `west` reporting that OpenOCD exited with an error. It does not say why. The printed command
sources `target/<chip>.cfg` (the example names `max32655.cfg`). One way to get exactly this output: if the OpenOCD you use has
no such file, OpenOCD aborts. Running Zephyr SDK 1.0.1's OpenOCD directly with `--log_output <file>` and `max32655.cfg` reproduced the
same failure: only the banner on the terminal, exit status 1, and `Can't find target/max32655.cfg` only in the log file;
`allow_low_pwr_dbg` and `init` never ran. That this is what happened in your own failing run is an inference, because the
pasted output has no reason line: to confirm, read the reason as described below.

Where the reason appears depends on the command `west` printed (`west` adds `--log_output <file>` only when its runner has a log file set):

- (a) The command contains `--log_output <build>/openocd.log` (as in the example): the terminal shows only the banner and the
  `FATAL ERROR` line, and the reason is in that log. Read it with `tail <build>/openocd.log`.
- (b) The command has no `--log_output`: OpenOCD's messages print above `FATAL ERROR`. This ran without a board for `max78000`,
  and no `build/openocd.log` was created.
- Either way you can run the printed command by hand, **without** the `--log_output <file>` option, to see the message on the terminal.

Also check which cfg the command names and whether your OpenOCD has it: see [Is my OpenOCD new enough?](#is-my-openocd-new-enough)
and the [coverage matrix](boards.md#openocd-target-file-coverage).

Then match the message:

1. `Can't find target/<chip>.cfg`: this OpenOCD has no file for your chip.
   See [`Can't find target/<chip>.cfg`](#cant-find-targetchipcfg). Zephyr SDK 1.0.1's OpenOCD lacks the file for `max32650`,
   `max32655`, `max32657`, `max32658`, `max32665`, `max78000` and `max78002` (ran without a board); it has `max32690`.
   Affected Zephyr boards, by the cfg each one needs:

   | Target cfg | Zephyr boards |
   | --- | --- |
   | `max32650.cfg` | `max32650evkit`, `max32650fthr`, `max32651evkit`, `ad_swiot1l_sl` |
   | `max32655.cfg` | `max32655evkit`, `max32655fthr` |
   | `max32657.cfg` | `max32657evkit` |
   | `max32658.cfg` | `max32658evkit` |
   | `max32665.cfg` | `max32666evkit`, `max32666fthr` |
   | `max78000.cfg` | `max78000evkit`, `max78000fthr` |
   | `max78002.cfg` | `max78002evkit` |

2. `Error: unable to find a matching CMSIS-DAP device`: the cfg exists and the next suspect is a board not attached to WSL.
   See [the next entry](#error-unable-to-find-a-matching-cmsis-dap-device) and the
   [usbipd section](../README.md#connect-your-board-to-wsl).
3. An error about `allow_low_pwr_dbg` (it is on the printed command line): that OpenOCD does not have the command.
   The MSDK's OpenOCD (`Analog Devices 0.12.0-1.0.0-7`) is one that does not.

What ran without a board attached:

- Ran without a board: `west flash` for the APARD32690 with Zephyr SDK 1.0.1's own OpenOCD (`0.12.0-01050-g91bd278a5`) printed
  `Error: libusb initialization failed: Other error` and `Error: unable to find a matching CMSIS-DAP device`,
  then the `FATAL ERROR: command exited with status 1` line (the same failure as the example). The cfg and command exist there.
- Ran without a board: the same with an earlier fork build installed in `/usr/local` on the test machine (`/usr/local/bin/openocd`; `west flash --openocd ... --openocd-search ...`): `Error: unable to find a matching CMSIS-DAP device`,
  then the same `FATAL ERROR` line.
- Ran without a board: for a MAX78000 board, Zephyr SDK 1.0.1's OpenOCD printed `Can't find target/max78000.cfg` before `FATAL ERROR`.

**Probed with a board** (read-only: `init` and `targets` only; a MAX78000-class board was attached, nothing was flashed or reset; see
[Probed with a board](boards.md#probed-with-a-board)):

- Zephyr SDK 1.0.1's OpenOCD with `max32690.cfg` connected to the probe and a Cortex-M4 (state `running`). This shows the SDK's OpenOCD can talk to this probe with a config it has.
  It does not show that a MAX32690 board connects or flashes.
- Zephyr SDK 1.0.1's OpenOCD with `max78000.cfg` still printed `Can't find target/max78000.cfg` with the board attached.

**Reproduced with a board (MAX78000FTHR attached):** plain `west flash -d <build>` with no flags used the Zephyr SDK 1.0.1 OpenOCD pinned in `runners.yaml`
and printed `-- west flash: using runner openocd`, `Flashing file: <build>/zephyr/zephyr.hex`, the banner `Open On-Chip Debugger 0.12.0-01050-g91bd278a5 (2026-03-25-02:24)`,
`Can't find target/max78000.cfg` and `FATAL ERROR: command exited with status 1: ...`. This is case (b) above: the reason is on the terminal, no `build/openocd.log` was created, and nothing was flashed.
The cause is the missing `max78000.cfg` in that OpenOCD. The fix is the [ADI fork](../README.md#build-adi-openocd): with it the same board was **flashed** (via `west flash --openocd ... --openocd-search ...`).

**Untested with a board:** whether `max32690` boards flash with Zephyr SDK 1.0.1's OpenOCD.

Plain `west flash` with the Zephyr SDK's own OpenOCD was reported not to work for these boards; the fork is the verified and recommended path in this guide.
That is reproduced for the MAX78000FTHR (above). The `max32655` error in the example is explained only by analogy (an inference: the SDK's OpenOCD also lacks `max32655.cfg`), not reproduced with a board. The measured facts are above and in the [coverage matrix](boards.md#openocd-target-file-coverage).
If the wrong OpenOCD runs, see [Already have an OpenOCD installed?](../README.md#already-have-an-openocd-installed-make-sure-the-right-one-runs).

Fix: for boards whose cfg your SDK's OpenOCD lacks,

- Main path: build and use the [ADI OpenOCD fork](../README.md#build-adi-openocd) and [flash with it](../README.md#flash).
- Alternative: [flash with the MSDK's OpenOCD](alternative-msdk.md) (its script does not use `allow_low_pwr_dbg`).

## `Can't find target/<chip>.cfg`

> **MAX78000FTHR, max78000, max32655, max78002, max32650, max32665, max32657 or max32658 boards: do this.**
> Build the [ADI OpenOCD fork](../README.md#build-adi-openocd), set `OPENOCD_PREFIX` to its install prefix, then run from `<ZEPHYR_DIR>`:
> `west flash --openocd "$OPENOCD_PREFIX/bin/openocd" --openocd-search "$OPENOCD_PREFIX/share/openocd/scripts"` (flashed on a MAX78000FTHR; the other chips are untested).

Example (MAX78000FTHR attached, Zephyr SDK 1.0.1's OpenOCD): `Can't find target/max78000.cfg`. This OpenOCD has no target file for that chip.

Ran without a board: the OpenOCD in Zephyr SDK 0.17.4 (`0.12.0-01018-gb89d626c6`) has only `max32620`, `max32625` and `max3263x`
target files and prints `Can't find target/max32690.cfg`. Zephyr SDK 1.0.1's OpenOCD has `max32690.cfg` but not, for example, `max32655.cfg` or `max78000.cfg`
(see the [coverage matrix](boards.md#openocd-target-file-coverage)). The MSDK's OpenOCD and the ADI fork build used here have those.

Fix: use an OpenOCD that has the file.

- Zephyr v4.5.0 needs Zephyr SDK 1.0 or newer anyway ([Install the Zephyr SDK](../README.md#4-install-the-zephyr-sdk)).
- For boards the SDK's OpenOCD does not have, use the [ADI fork](../README.md#build-adi-openocd) or the [MSDK](alternative-msdk.md).
- Make sure the OpenOCD you think is running is the one that runs: `which -a openocd` (see [Check which OpenOCD runs](../README.md#4-check-which-openocd-runs) and [Already have an OpenOCD installed?](../README.md#already-have-an-openocd-installed-make-sure-the-right-one-runs)).

## `Error: unable to find a matching CMSIS-DAP device`

OpenOCD loaded its files but found no debug adapter. A board that is not attached to WSL is the first thing to rule out.
On WSL `Error: libusb initialization failed: Other error` may appear just before it.
Both lines appeared here when run without a board. With a board attached, the same probe commands connected instead (see [Probed with a board](boards.md#probed-with-a-board)); other causes were not tried.

1. In WSL run `lsusb`. You should see the debugger. Probed with a board: `ID 0d28:0204 NXP ARM mbed` (the text depends on the probe firmware). If not, the board is not attached.
2. On Windows run `usbipd list` and check that the board's `STATE` is `Attached`; if not, run
   `usbipd attach --wsl --busid <BUSID>` again. See [Connect your board to WSL](../README.md#connect-your-board-to-wsl).
3. The attachment is lost when you unplug the board, reboot, or restart WSL. Replug, or try another cable (some are charge-only) or port.
4. Use the board's debug USB port, not a power-only one.

If `lsusb` shows the debugger and the error remains, that is not covered here (an adapter problem was not tried; for permission errors see the next entry).

## Access denied / permission error opening the probe

Use this entry if OpenOCD reports an access or permission error opening the USB probe,
instead of `unable to find a matching CMSIS-DAP device`, and `lsusb` already shows the probe.

OpenOCD ships a udev rules file, `contrib/60-openocd.rules`. In the ADI fork it is in your clone: `~/adi-openocd/contrib/60-openocd.rules`.
What the file contains (read from a recent checkout of the fork's default branch; the tag in this guide was not read separately):

- Its header says "Copy this file to /etc/udev/rules.d/" and to refresh with `udevadm control --reload`.
- Its entries (for USB, tty and hidraw devices, mostly listed by VID:PID) set `MODE="660", GROUP="plugdev", TAG+="uaccess"`.
- It has no VID:PID entry for VID `0d28` (the DAPLink-style example used in this guide), but it ends with a catch-all line under `# CMSIS-DAP compatible adapters`:
  `ATTRS{product}=="*CMSIS-DAP*", MODE="660", GROUP="plugdev", TAG+="uaccess"`. I checked this with `grep` in a local checkout of the fork (`contrib/60-openocd.rules`, commit `8d754a249`, not the pinned tag)
  and in the `/etc/udev/rules.d/60-openocd.rules` installed on the machine used here.

**Probed with a board:** on a WSL with systemd on (`systemd=true` in `/etc/wsl.conf`, `systemd-udevd` active), with the user in group `plugdev` and the probe's USB node
`crw-rw---- root plugdev`, OpenOCD opened the `0d28:0204` probe as a normal user without `sudo`. This worked because the installed `60-openocd.rules` has the generic line above
(it matches product strings containing `CMSIS-DAP`; this probe's product string is `DAPLink_CMSIS-DAP`), not because of a `0d28` line:
`udevadm test` on the probe printed `/etc/udev/rules.d/60-openocd.rules:158 GROUP 46` and `:158 MODE 0660`.
So you need a VID:PID line only if your probe's product string does not contain `CMSIS-DAP`, or your rules file lacks the generic line
(everything below this point was **untested**: no rule was added or reloaded and `sudo` was not used).

Example line for a probe with VID `0d28` and PID `0204`, in the same format as the file's own lines. For DAPLink-style probes whose product string contains `CMSIS-DAP`
it is probably redundant; keep it for other cases (**untested**; change the VID:PID to your probe's `lsusb` output):

```text
ATTRS{idVendor}=="0d28", ATTRS{idProduct}=="0204", MODE="660", GROUP="plugdev", TAG+="uaccess"
```

Install and reload the rules (**untested**, needs `sudo`). Copy the file first:

```bash
sudo cp ~/adi-openocd/contrib/60-openocd.rules /etc/udev/rules.d/
```

If your probe is not listed, now edit the copy in `/etc/udev/rules.d/` (for example `sudo nano /etc/udev/rules.d/60-openocd.rules`) and add the example line
before the `LABEL="openocd_rules_end"` line at the end of the file. Then reload:

```bash
sudo udevadm control --reload-rules && sudo udevadm trigger
```

The rules use the group `plugdev`. Check whether you are in it, and add yourself if not (**untested**):

```bash
groups
sudo usermod -aG plugdev "$USER"
```

A new group membership applies after you log in again; on WSL, run `wsl --shutdown` in PowerShell, then reopen WSL and attach the board again.
This needs udev to be running in your WSL distribution. On the setup observed it was (see above); no upstream
document is cited for enabling it.
If udev is not running on your WSL, run the flash command with `sudo -E` as a last resort (**untested**):
`sudo -E env "PATH=$PATH" west flash ...` (`env "PATH=$PATH"` keeps your venv's `west` on the path).
Warning: if the build is stale, `west flash` may rebuild as root and leave root-owned files in `build/`. Build as your own user first.

## `libncurses.so.5: cannot open shared object file` (or `libtinfo.so.5`)

Ubuntu 24.04 dropped `libncurses5`. Only the MSDK's `arm-none-eabi-gdb` needs it (this entry is about the MSDK gdb, not about flashing).
Zephyr's own gdb (`arm-zephyr-eabi-gdb`) does not, so you can skip this if you do not use MSDK gdb.

The fix is to install the Ubuntu 22.04 packages (needs `sudo`; verified in a clean Ubuntu 24.04 container, where the `.deb` files were downloaded on the host because of a proxy, see the [proxy entry](#server-certificate-verification-failed-behind-a-corporate-proxy)):

```bash
cd "$(mktemp -d)"
BASE=https://security.ubuntu.com/ubuntu/pool/universe/n/ncurses
wget $BASE/libtinfo5_6.3-2ubuntu0.3_amd64.deb $BASE/libncurses5_6.3-2ubuntu0.3_amd64.deb
sudo apt install ./libtinfo5_6.3-2ubuntu0.3_amd64.deb ./libncurses5_6.3-2ubuntu0.3_amd64.deb
```

`sudo apt install ./file.deb` does not check a signature, so the https download from Ubuntu's security archive is the trust anchor here.

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

Results here for `max32690` (run without a board; the `allow_low_pwr_dbg` counts were identical when re-checked with a board attached, host-only and without `init`): the second column is the `find` check, the third the `info commands` check above (run after loading the
cmsis-dap and target files, which end with `Error: unable to find a matching CMSIS-DAP device` with no board). The fork row is the
build at `/usr/local/bin/openocd` (built 2026-03-11, no tag in its version string), not necessarily tag `0.12.0-1.4.0`.

| OpenOCD | `find target/max32690.cfg` | `allow_low_pwr_dbg count` |
| --- | --- | --- |
| MSDK `Analog Devices 0.12.0-1.0.0-7` | found | 0 |
| ADI fork (`/usr/local` build) | found | 1 |
| Zephyr SDK 1.0.1 | found | 1 |
| Zephyr SDK 0.17.4 | `Can't find target/max32690.cfg` | not run |

Version drift: the Zephyr SDK and the upstream/ADI OpenOCD change over time, and the table above is a snapshot.
See the ADI fork's [tags](https://github.com/analogdevicesinc/openocd/tags) and the Zephyr SDK [releases](https://github.com/zephyrproject-rtos/sdk-ng/releases) for newer versions.
If a newer Zephyr SDK ships an OpenOCD that passes both checks for your chip, the default `west flash` may work without
the fork; try it with your board attached and report what happens. Zephyr's own `west flash` command line (printed on failure) shows
which target file and commands it needs, and
`<ZEPHYR_DIR>/boards/common/openocd-adi-max32.boards.cmake` is where they are set.
Passing both checks only shows that the file and command exist, not that flashing works (**untested with a board**).

## `invalid command name "init_qspi"` on the MAX32690 (ADI fork 0.12.0-1.4.0)

Reported on an APARD32690 flashed with `west flash --openocd "$OPENOCD_PREFIX/bin/openocd" ...` (the fork built at tag `0.12.0-1.4.0`). `reset init` fails and the flash does not happen:

```text
Error: [max32xxx.cpu] Execution of event reset-deassert-post failed:
.../target/max32690.cfg:177: Error: invalid command name "init_qspi"
```

Likely cause (read from the config; not reproduced on a MAX32690 here): in that tag `proc init_qspi` is defined only when `MAX32_QSPI_ENABLE` is 1, which is the default off, but the two event handlers that call `init_qspi` (lines 167 and 177) are outside that `if`. Tag `0.12.0-1.3.1` has the calls inside it.

Easiest fix for a MAX32690: **plain `west flash`**. The Zephyr SDK 1.0.1 OpenOCD has `max32690.cfg` without this problem, and plain `west flash` wrote an APARD32690 in a user report.
Use the fork only for boards the SDK lacks (see the [coverage matrix](boards.md#openocd-target-file-coverage)).

A user guarded the two `init_qspi` calls with `if {$_QSPI_ENABLE == 1} { ... }` in the installed `max32690.cfg`, and **that did not fix the flash**, so no workaround for the fork is documented here.
The cause is read from the config and not reproduced on a MAX32690 here, so it may be incomplete.
Use plain `west flash` for this board, or check whether a newer ADI fork release fixes it (see [Is my OpenOCD new enough?](#is-my-openocd-new-enough)).

## Flash says `wrote N bytes` but nothing runs

Check you built for the board you flashed. A hex built for a different board writes fine and then shows nothing. In one report the build was for a MAX78000EVKIT while the board was an APARD32690, so the LED stayed off and the console was silent. Rebuild with the right name:

```bash
west build -p always -b apard32690/max32690/m4 samples/basic/blinky
west flash
```

`west boards --format "{name}" | grep -i <chip>` lists the names. Blinky drives `led0`, which on the APARD32690 is the blue LED (LED1), and prints `LED state: ON/OFF` on the serial console.
