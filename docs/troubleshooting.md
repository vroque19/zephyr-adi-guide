# Troubleshooting

- [`west zephyr-export` fails with `ModuleNotFoundError: No module named 'jsonschema'`](#west-zephyr-export-fails-with-modulenotfounderror-no-module-named-jsonschema)
- [`west flash` fails with `FATAL ERROR` or `Can't find target/<chip>.cfg`](#west-flash-fails-with-fatal-error-or-cant-find-targetchipcfg)
- [`Error: unable to find a matching CMSIS-DAP device`](#error-unable-to-find-a-matching-cmsis-dap-device)
- [Access denied / permission error opening the probe](#access-denied--permission-error-opening-the-probe)
- [`invalid command name "init_qspi"` on the MAX32690 (ADI fork 0.12.0-1.4.0)](#invalid-command-name-init_qspi-on-the-max32690-adi-fork-0120-140)
- [Flash says `wrote N bytes` but nothing runs](#flash-says-wrote-n-bytes-but-nothing-runs)
- [Serial output is garbage](#serial-output-is-garbage)
- [`server certificate verification failed` behind a corporate proxy](#server-certificate-verification-failed-behind-a-corporate-proxy)
- [`libncurses.so.5: cannot open shared object file`](#libncursesso5-cannot-open-shared-object-file-or-libtinfoso5)
- [Is my OpenOCD new enough?](#is-my-openocd-new-enough)

## `west zephyr-export` fails with `ModuleNotFoundError: No module named 'jsonschema'`

`west zephyr-export` ran before `west packages pip --install` on a fresh machine. The error ends with `ModuleNotFoundError: No module named 'jsonschema'`,
followed by `AttributeError: 'NoneType' object has no attribute 'err'`.

Fix: with the venv active, run `west packages pip --install`, then `west zephyr-export`.

## `west flash` fails with `FATAL ERROR` or `Can't find target/<chip>.cfg`

```text
FATAL ERROR: command exited with status 1: <SDK>/hosttools/sysroots/x86_64-pokysdk-linux/usr/bin/openocd -s <SDK>/.../scripts --log_output <ZEPHYR_DIR>/build/openocd.log ... -c 'source [find target/max32655.cfg]' -c allow_low_pwr_dbg ...
```

This line only says OpenOCD exited with an error. The reason is either printed above it, or, when the command has `--log_output <file>`, only in that log file: `tail <ZEPHYR_DIR>/build/openocd.log`.
You can also run the printed command by hand without `--log_output`.

Match the reason:

1. **`Can't find target/<chip>.cfg`:** the OpenOCD that ran has no file for your chip. This is the usual case. The Zephyr SDK 1.0.1's OpenOCD lacks
   `max32650`, `max32655`, `max32657`, `max32658`, `max32665`, `max78000` and `max78002` (it has `max32690`; see the [coverage table](boards.md#which-openocd-has-your-chip)).
   Fix: [build ADI's fork](../README.md#5-build-adis-openocd) and flash with it, or use the [MSDK script](alternative-msdk.md).
   Also run `which -a openocd` to make sure the OpenOCD you think is running is the one that runs.
2. **`unable to find a matching CMSIS-DAP device`:** see the next entry.
3. **An error about `allow_low_pwr_dbg`:** that OpenOCD lacks the command. The MSDK's does.

Zephyr boards by the target file they need:

| Target cfg | Zephyr boards |
| --- | --- |
| `max32650.cfg` | `max32650evkit`, `max32650fthr`, `max32651evkit`, `ad_swiot1l_sl` |
| `max32655.cfg` | `max32655evkit`, `max32655fthr` |
| `max32657.cfg` | `max32657evkit` |
| `max32658.cfg` | `max32658evkit` |
| `max32665.cfg` | `max32666evkit`, `max32666fthr` |
| `max78000.cfg` | `max78000evkit`, `max78000fthr` |
| `max78002.cfg` | `max78002evkit` |

## `Error: unable to find a matching CMSIS-DAP device`

OpenOCD loaded its files but found no debug probe. Rule out an unattached board first. On WSL, `Error: libusb initialization failed: Other error` may appear just before it.

1. In WSL run `lsusb`. You should see the probe (the MAX78000FTHR shows `0d28:0204 NXP ARM mbed`). If not, it isn't attached.
2. On Windows run `usbipd list`. The board's `STATE` must be `Attached`; if not, run `usbipd attach --wsl --busid <BUSID>` again ([step 4](../README.md#4-connect-the-board-to-wsl)).
3. The attachment is lost when you unplug the board, reboot, or restart WSL. Try another cable (some are charge-only) or port.
4. Use the board's debug USB port, not a power-only one.

## Access denied / permission error opening the probe

Use this if OpenOCD reports an access or permission error, `lsusb` shows the probe, and you are not seeing `unable to find a matching CMSIS-DAP device`.

OpenOCD ships a udev rules file. With the fork it is `~/adi-openocd/contrib/60-openocd.rules`. Install it, reload udev and add yourself to its group (`plugdev`):

```bash
sudo cp ~/adi-openocd/contrib/60-openocd.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules && sudo udevadm trigger
sudo usermod -aG plugdev "$USER"
```

Then run `wsl --shutdown` in PowerShell, reopen WSL and attach the board again. This needs udev running in your WSL distribution.
The file has a generic rule for probes whose product string contains `CMSIS-DAP`. If yours doesn't, add a line for its VID:PID (from `lsusb`) before `LABEL="openocd_rules_end"`:

```text
ATTRS{idVendor}=="0d28", ATTRS{idProduct}=="0204", MODE="660", GROUP="plugdev", TAG+="uaccess"
```

On the maintainer's WSL (systemd on, user in `plugdev`) the probe opened without any change. These rule steps were not run. As a last resort, run the flash with `sudo -E env "PATH=$PATH" west flash ...`, after building as your own user, so root doesn't own files in `build/`.

## `invalid command name "init_qspi"` on the MAX32690 (ADI fork 0.12.0-1.4.0)

Reported on an APARD32690 flashed with `west flash --openocd "$OPENOCD_PREFIX/bin/openocd" ...`. `reset init` fails and nothing is written:

```text
Error: [max32xxx.cpu] Execution of event reset-deassert-post failed:
.../target/max32690.cfg:177: Error: invalid command name "init_qspi"
```

Likely cause (read from the config, not reproduced here): in tag `0.12.0-1.4.0`, `proc init_qspi` exists only when `MAX32_QSPI_ENABLE` is 1 (off by default), but two event handlers call it unconditionally (lines 167 and 177).
Tag `0.12.0-1.3.1` has the calls inside the `if`.

**Fix: use plain `west flash`.** The Zephyr SDK 1.0.1's OpenOCD has a working `max32690.cfg`, and plain `west flash` flashed an APARD32690 in a user report.
Guarding the two calls with `if {$_QSPI_ENABLE == 1} { ... }` did not fix it for that user, so no patch for the fork is given. Check whether a newer fork release fixes it ([below](#is-my-openocd-new-enough)).

## Flash says `wrote N bytes` but nothing runs

Check you built for the board you flashed. A hex built for another board writes fine and then shows nothing. In one report the build was for a MAX78000EVKIT while the board was an APARD32690, so the LED stayed off and the console was silent. Rebuild with the right name:

```bash
west build -p always -b apard32690/max32690/m4 samples/basic/blinky
west flash
```

`west boards --format "{name}" | grep -i <chip>` lists the names. Blinky drives `led0`, the blue LED (LED1) on the APARD32690, and prints `LED state: ON/OFF` on the serial console.

## Serial output is garbage

`cat /dev/ttyACM0` after `stty -F /dev/ttyACM0 115200 raw -echo` prints random bytes instead of `*** Booting Zephyr OS build ... ***`, even though `stty -a` says 115200.
Seen on a MAX78000FTHR. Force a real baud change first, then reset the board:

```bash
stty -F /dev/ttyACM0 9600 raw -echo; stty -F /dev/ttyACM0 115200 raw -echo; cat /dev/ttyACM0
```

The cause isn't confirmed. A guess is that `stty` does nothing when the driver already thinks the port is at 115200, so the probe's UART bridge keeps another rate.
With minicom, also set "Hardware Flow Control" to No (Ctrl-A, O, "Serial port setup").

## `server certificate verification failed` behind a corporate proxy

`git clone --recurse-submodules` of the OpenOCD fork fails with `server certificate verification failed` (the `libjaylink` submodule comes from `https://gitlab.zapb.de`),
or `wget` says `Self-signed certificate encountered` for `security.ubuntu.com`. Seen only inside Docker behind a TLS-inspecting proxy.

Fix: ask IT for your organisation's root CA certificate, copy it to `/usr/local/share/ca-certificates/<name>.crt` and run `sudo update-ca-certificates` (not tried).
Don't disable certificate verification (`wget --no-check-certificate`, `GIT_SSL_NO_VERIFY`). A workaround that worked: download on a machine that isn't intercepted and copy the files in.

## `libncurses.so.5: cannot open shared object file` (or `libtinfo.so.5`)

Ubuntu 24.04 dropped `libncurses5`. Only the MSDK's `arm-none-eabi-gdb` needs it; Zephyr's own `arm-zephyr-eabi-gdb` doesn't, and flashing doesn't. Install the Ubuntu 22.04 packages:

```bash
cd "$(mktemp -d)"
BASE=https://security.ubuntu.com/ubuntu/pool/universe/n/ncurses
wget $BASE/libtinfo5_6.3-2ubuntu0.3_amd64.deb $BASE/libncurses5_6.3-2ubuntu0.3_amd64.deb
sudo apt install ./libtinfo5_6.3-2ubuntu0.3_amd64.deb ./libncurses5_6.3-2ubuntu0.3_amd64.deb
```

If those file names stop resolving, browse the `BASE` URL for the current `.deb` files.

## Is my OpenOCD new enough?

Replace `<openocd>` with the binary, `<scripts>` with its scripts directory and `<chip>` with your target (`max32690`, `max78000`, ...).

1. Does it have the target file? This prints the path, or `Can't find target/<chip>.cfg`:

   ```bash
   <openocd> -s <scripts> -c 'puts [find target/<chip>.cfg]' -c shutdown
   ```

2. Does it have the `allow_low_pwr_dbg` command that `west flash` sends? This prints `1` if so, `0` if not (it ends with a CMSIS-DAP error if no board is attached):

   ```bash
   <openocd> -s <scripts> -c 'source [find interface/cmsis-dap.cfg]' -c 'source [find target/<chip>.cfg]' -c 'puts "allow_low_pwr_dbg count: [llength [info commands allow_low_pwr_dbg]]"' -c shutdown
   ```

Results for `max32690`: the MSDK's OpenOCD has the file and no command (`0`); the ADI fork and the Zephyr SDK 1.0.1 have both; Zephyr SDK 0.17.4 has no file.
Newer versions: see the ADI fork's [tags](https://github.com/analogdevicesinc/openocd/tags) and the Zephyr SDK [releases](https://github.com/zephyrproject-rtos/sdk-ng/releases).
Having the file and the command doesn't prove flashing works. `<ZEPHYR_DIR>/boards/common/openocd-adi-max32.boards.cmake` shows what `west flash` asks for.
