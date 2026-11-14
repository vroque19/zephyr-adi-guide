# Zephyr on ADI boards

Get from a fresh WSL install (Ubuntu 24.04) to a flashed Analog Devices board running Zephyr.

It follows the official [Zephyr Getting Started](https://docs.zephyrproject.org/latest/develop/getting_started/index.html)
and adds what that page leaves out for ADI boards: sharing the USB debugger with WSL and flashing with OpenOCD.
The examples use the MAX78000FTHR. For another board, change the board name: see [docs/boards.md](docs/boards.md).

## The OpenOCD problem

`west flash` uses the OpenOCD inside the Zephyr SDK, and it has no target file for several ADI chips (`max78000`, `max32655`, `max32665`, ...).
Flashing fails with `Can't find target/max78000.cfg`. The fix is to build ADI's own OpenOCD fork (step 5) and point `west flash` at it.

MAX32690 boards (such as the APARD32690) are the exception: the SDK's OpenOCD supports them, so plain `west flash` works and you can skip step 5.

## 1. Hardware

- **MAX78000FTHR:** a debug probe is on the board. Plug in its USB port.
- **APARD32690, MAX32655EVKIT, MAX78000EVKIT:** connect an external CMSIS-DAP probe to the board's SWD header (`P9`, `JH3`, `JH5`). Check the board's user guide.

Use a data USB cable. Charge-only cables do not work.

## 2. Host packages

```bash
sudo apt update
sudo apt install --no-install-recommends git cmake ninja-build gperf \
  ccache dfu-util device-tree-compiler wget python3-dev python3-venv python3-tk \
  xz-utils file make gcc gcc-multilib g++-multilib libsdl2-dev libmagic1t64 usbutils
```

On ARM64 WSL, leave out `gcc-multilib` and `g++-multilib`.

## 3. Zephyr

These are the official steps. About 10 GB of disk is used, so check `df -h ~` first.

```bash
python3 -m venv ~/zephyrproject/.venv
source ~/zephyrproject/.venv/bin/activate
pip install west
west init -m https://github.com/zephyrproject-rtos/zephyr ~/zephyrproject
cd ~/zephyrproject
west update
west packages pip --install
west zephyr-export
cd zephyr
west sdk install
```

Run the `source` line again in every new terminal.
Keep `west packages pip --install` before `west zephyr-export`; the other way round fails on a fresh machine ([why](docs/troubleshooting.md#west-zephyr-export-fails-with-modulenotfounderror-no-module-named-jsonschema)).

Tips:

- This guide was run with Zephyr v4.5.0. To use that exact release, add `--mr v4.5.0` to `west init`.
- `west sdk install` downloads every toolchain (several GB). `west sdk install --gnu-toolchains arm-zephyr-eabi` installs only the ARM one (about 250 MB), which is enough for ADI Cortex-M parts.

Build `hello_world` (find your board name with `west boards | grep -i max78000`):

```bash
west build -p always -b max78000fthr/max78000/m4 samples/hello_world
```

This must create `build/zephyr/zephyr.hex`. For other samples, such as `samples/basic/blinky`, only the path changes.
Make sure the board name matches the board you flash. A hex built for another board flashes fine and then does nothing.

## 4. Connect the board to WSL

WSL cannot see USB devices by itself. [usbipd-win](https://github.com/dorssel/usbipd-win) shares one with it.

In PowerShell on Windows:

```powershell
winget install --interactive --exact dorssel.usbipd-win
usbipd list
```

Close and reopen PowerShell after the install. In the `usbipd list` output, find your debug probe (often named `CMSIS-DAP` or `DAPLink`) and note its `BUSID`, like `2-4`.
Then bind it once (PowerShell **as Administrator**) and attach it (any PowerShell):

```powershell
usbipd bind --busid <BUSID>
usbipd attach --wsl --busid <BUSID>
```

You have to attach again after unplugging the board, rebooting or restarting WSL. `--auto-attach` does it automatically.

Check from WSL:

```bash
lsusb
ls /dev | grep -E '^tty(ACM|USB)'
```

You should see the probe in `lsusb` (the MAX78000FTHR shows `0d28:0204 NXP ARM mbed`) and a serial port such as `/dev/ttyACM0`.
If not, attach it again. If OpenOCD later says access denied, see [troubleshooting](docs/troubleshooting.md#access-denied--permission-error-opening-the-probe).

## 5. Build ADI's OpenOCD

Skip this for MAX32690 boards.

```bash
sudo apt install build-essential git autoconf automake libtool pkg-config \
  libusb-1.0-0-dev libjim-dev libjaylink-dev libhidapi-dev
git clone --recurse-submodules --branch 0.12.0-1.4.0 https://github.com/analogdevicesinc/openocd ~/adi-openocd
cd ~/adi-openocd
export OPENOCD_PREFIX="$HOME/.local"
./bootstrap
./configure --prefix="$OPENOCD_PREFIX"
make -j"$(nproc)"
make install
```

`OPENOCD_PREFIX` lasts for this terminal only. Add `export OPENOCD_PREFIX="$HOME/.local"` to `~/.bashrc` to keep it.
Behind a corporate proxy the clone can fail on a certificate error: [troubleshooting](docs/troubleshooting.md#server-certificate-verification-failed-behind-a-corporate-proxy).

Check that this OpenOCD is the one you will run:

```bash
"$OPENOCD_PREFIX/bin/openocd" --version
which -a openocd
```

The fork prints `Open On-Chip Debugger (PKGVERSION)`. Any other `openocd` on your `PATH` (the MSDK's, an old system one) is not the fork, so always pass the full path below.

## 6. Flash

With the venv active and the board attached:

```bash
cd ~/zephyrproject/zephyr
west flash --openocd "$OPENOCD_PREFIX/bin/openocd" --openocd-search "$OPENOCD_PREFIX/share/openocd/scripts"
```

For a MAX32690 board such as the APARD32690, use plain `west flash`.

Success ends with lines like:

```text
auto erase enabled
wrote 24576 bytes from file <path>/zephyr.hex in 1.17s (20.5 KiB/s)
shutdown command invoked
```

If you flash often, put the long command in an alias in `~/.bashrc`:

```bash
alias wflash='west flash --openocd "$OPENOCD_PREFIX/bin/openocd" --openocd-search "$OPENOCD_PREFIX/share/openocd/scripts"'
```

## 7. See it run

`hello_world` prints on the board's serial port. In one terminal, start a reader (`minicom -D /dev/ttyACM0 -b 115200` also works):

```bash
stty -F /dev/ttyACM0 9600 raw -echo; stty -F /dev/ttyACM0 115200 raw -echo; cat /dev/ttyACM0
```

In a second terminal, reset the board (use your chip for `max78000`):

```bash
"$OPENOCD_PREFIX/bin/openocd" -s "$OPENOCD_PREFIX/share/openocd/scripts" \
  -c 'source [find interface/cmsis-dap.cfg]' -c 'source [find target/max78000.cfg]' \
  -c init -c 'reset run' -c shutdown
```

You should see:

```text
*** Booting Zephyr OS build v4.5.0 ***
Hello World! max78000fthr/max78000/m4
```

Garbage characters or nothing: [troubleshooting](docs/troubleshooting.md#serial-output-is-garbage). Press Ctrl+C to stop `cat`.

## More

- [docs/boards.md](docs/boards.md): other boards, and which OpenOCD supports which chip.
- [docs/alternative-msdk.md](docs/alternative-msdk.md): flash with the MSDK's OpenOCD and a script instead of building the fork.
- [docs/troubleshooting.md](docs/troubleshooting.md): `west flash` errors and other problems.
- `scripts/flash-adi-fork.sh` and `scripts/flash-msdk.sh`: helper scripts for step 6 and the MSDK path.

Only the MAX78000FTHR was flashed by the maintainer, in a clean Ubuntu 24.04 container with the board passed through from WSL2. A user also flashed an APARD32690.
Other boards and steps may differ. Please open an issue with the board, the OpenOCD you used and what happened.

## License

[MIT](LICENSE)
