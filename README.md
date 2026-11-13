# Zephyr on ADI boards

Get from a fresh WSL install to a flashed Analog Devices board running Zephyr.

This guide is for people who run Zephyr on ADI (MAX32xxx / MAX78xxx) boards from Windows with WSL.
It follows the official
[Zephyr Getting Started](https://docs.zephyrproject.org/latest/develop/getting_started/index.html)
and adds the parts it leaves out for ADI boards: sharing the USB debugger with WSL and flashing with OpenOCD.
It assumes you already have WSL with Ubuntu. Installing WSL is out of scope.
The examples use the MAX78000FTHR, the only board verified here. For other boards, change the board name: see [docs/boards.md](docs/boards.md).

**Status:** checked on one board, a MAX78000FTHR, with `samples/hello_world`. `west flash --openocd` with the pinned ADI OpenOCD fork, built and installed to `$HOME/.local` as in the Quick start,
wrote the program (**flashed**), and the program printed over serial after an explicit `reset run`. Both helper scripts also wrote it, and so did a `sudo make install` build in `/usr/local`.
Most of this ran in a clean Ubuntu 24.04 Docker container with the board passed through from a WSL2 host, so a real WSL install may differ (systemd/udev, default packages).
Everything else is **untested** unless marked otherwise.
What was run, where and when is in the [test log](docs/test-log.md).

| Status word | Meaning |
| --- | --- |
| **built** | A build succeeded here. |
| **ran without a board** | OpenOCD ran here with nothing attached. |
| **probed with a board** | Checked read-only with a board attached (OpenOCD `init` and `targets` only, or `lsusb`/`usbipd`/udev lookups). Nothing was flashed or reset. |
| **flashed** | A flash write to a board succeeded (OpenOCD printed `wrote N bytes`). "Confirmed running" means the board then printed `hello_world` over serial; that was observed only after the `west flash --openocd` run with the pinned fork, followed by `reset run`. |
| **untested** | Needs a board, `sudo` or an Administrator shell, and was not run. |

## Quick start

The short path. All steps are required, in order: step 4 builds the OpenOCD that step 5 uses.
This is the path that was run on the MAX78000FTHR. For other boards, change `-b`: see [docs/boards.md](docs/boards.md).

1. Get a debug probe if your board needs one (the MAX78000FTHR has one on board), then install the host packages: [Prerequisites](#prerequisites). **(ran in a clean Ubuntu 24.04 container, not on a real WSL install)**
   Hardware: see [Hardware you need](#hardware-you-need).
2. Set up Zephyr exactly as the official guide does and build `hello_world` for the MAX78000FTHR
   **(built with `--mr v4.5.0` pinned and an ARM-only SDK; the official commands below were not run as written, see [Zephyr setup](#zephyr-setup))**:

   ```bash
   python3 -m venv ~/zephyrproject/.venv && source ~/zephyrproject/.venv/bin/activate
   pip install west
   west init -m https://github.com/zephyrproject-rtos/zephyr ~/zephyrproject && cd ~/zephyrproject && west update
   west packages pip --install && west zephyr-export
   cd zephyr && west sdk install
   west build -p always -b max78000fthr/max78000/m4 samples/hello_world
   ```

3. Attach the board's debug probe to WSL with usbipd-win ([details](#connect-your-board-to-wsl)). First find the board's `<BUSID>` with `usbipd list`, then
   in an Administrator PowerShell, once: `usbipd bind --busid <BUSID>`, and in any PowerShell: `usbipd attach --wsl --busid <BUSID>`.
   **(untested: needs a Windows Administrator shell; the board was already attached when it was probed)**
4. Build ADI's OpenOCD fork at the pinned tag and install it to `$HOME/.local` ([details](#build-adi-openocd)).
   **(built and flashed from this install in a clean container; behind a TLS-inspecting proxy see [the proxy entry](docs/troubleshooting.md#server-certificate-verification-failed-behind-a-corporate-proxy))**

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

5. Open a second terminal and start the serial reader first: `ls /dev/ttyACM*`, then `stty -F /dev/ttyACM0 9600 raw -echo; stty -F /dev/ttyACM0 115200 raw -echo; cat /dev/ttyACM0` (the baud toggle is explained under [Verify it runs](#verify-it-runs)).
   On the test machine the node was world-readable (`crw-rw-rw- root dialout`); if you get "Permission denied" on another setup, adding yourself to `dialout` is the usual fix (**untested**).
   Then, in the first terminal, flash from the Zephyr directory with the venv active **(`west flash` wrote to a MAX78000FTHR, other boards untested)**:

   ```bash
   export OPENOCD_PREFIX="$HOME/.local"
   cd ~/zephyrproject/zephyr && source ~/zephyrproject/.venv/bin/activate
   west flash --openocd "$OPENOCD_PREFIX/bin/openocd" --openocd-search "$OPENOCD_PREFIX/share/openocd/scripts"
   ```

Expected result: OpenOCD prints these two lines (the byte count and speed vary with the program and the board):

```text
auto erase enabled
wrote 24576 bytes from file <path>/zephyr.hex in 1.17s (20.5 KiB/s)
```

`west flash` ends with `wrote N bytes`; the banner below was observed over serial after an explicit `reset run`, so reset once (or replug) if you see nothing.
Reset the board as in [Verify it runs](#verify-it-runs).
The serial reader then shows these two lines:

```text
*** Booting Zephyr OS build v4.5.0 ***
Hello World! max78000fthr/max78000/m4
```

Something broke? See [Troubleshooting](#troubleshooting).

## Contents

- [Versions used](#versions-used)
- [Which OpenOCD do I need?](#which-openocd-do-i-need)
- [Prerequisites](#prerequisites)
- [Zephyr setup](#zephyr-setup)
- [Connect your board to WSL](#connect-your-board-to-wsl)
- [Build ADI OpenOCD](#build-adi-openocd)
- [Flash](#flash)
- [Using a different board](#using-a-different-board)
- [Not covered yet](#not-covered-yet)
- [Troubleshooting](#troubleshooting)
- [Contributing and feedback](#contributing-and-feedback)
- [License](#license)

## Versions used

| Component | Version |
| --- | --- |
| Ubuntu (WSL) | 24.04 |
| Zephyr | v4.5.0 |
| Zephyr SDK | 1.0.1 (minimal SDK, host tools and `arm-zephyr-eabi` toolchain only) |
| west | 1.5.0 |
| Python | 3.12.3 |
| Boards built | `max78000fthr/max78000/m4` (built and **flashed**, the only board flashed), `apard32690/max32690/m4` (revision D), `max78000evkit/max78000/m4`, `max32655evkit/max32655/m4` (built, not flashed): see [docs/boards.md](docs/boards.md) |
| ADI OpenOCD fork | tag `0.12.0-1.4.0` (commit `ad75bfb79b509634b92646b9e65b958f3ea1d8bf`); built from the steps below and used to flash the MAX78000FTHR. The version line prints the literal text `(PKGVERSION)`. Details: [test log](docs/test-log.md) |
| MSDK (alternative path only) | Install the current release from ADI. No version file is shipped |
| MSDK toolchain / OpenOCD (alternative path only) | The MSDK tested had GNU Arm toolchain 10.3-2021.10 and OpenOCD "Analog Devices 0.12.0-1.0.0-7" |

The venv, `west init`, `west update` and the build were run from scratch in a clean shell; the Python packages were already installed on that machine, which hid the order problem in step 3, found later in a [clean container](docs/test-log.md#clean-container-test-ubuntu-2404). The SDK install was run once (a real download, with no 1.0.x SDK present) and re-run later as a no-op.

## Which OpenOCD do I need?

A `cfg` in this guide is an OpenOCD target config file such as `target/max32690.cfg`.

Short answer: the main path uses [ADI's OpenOCD fork](#build-adi-openocd) with `west flash`.
The OpenOCD in the Zephyr SDK lacks target files for several ADI chips, and the MSDK's OpenOCD lacks the `allow_low_pwr_dbg` command that `west flash` sends.

- Which chips each OpenOCD supports: [coverage matrix](docs/boards.md#openocd-target-file-coverage).
- Using the MSDK's OpenOCD instead: [docs/alternative-msdk.md](docs/alternative-msdk.md).
- `west flash` errors: [docs/troubleshooting.md](docs/troubleshooting.md).

## Prerequisites

### Hardware you need

The boards in this guide, except the MAX78000FTHR, need a CMSIS-DAP-compatible debug probe connected over SWD to the board's debug header.
Per Zephyr's own board docs:

- MAX78000FTHR: a MAX32625 on the board is preprogrammed with DAPLink firmware, so debugging and programming work over its USB port. No extra probe.
- APARD32690: connect an external debug probe to the SWD header `P9`.
- MAX32655EVKIT: connect an external debug probe to the SWD header `JH3`.
- MAX78000EVKIT: connect an external debug probe to the SWD header `JH5`.

The default `west flash` settings for these boards use OpenOCD's `cmsis-dap.cfg` interface file (set in
`<ZEPHYR_DIR>/boards/common/openocd-adi-max32.boards.cmake`), so a different probe type needs a different interface config.
(That shared file already uses `jlink.cfg` for MAX32657 boards.) Check your board's user guide for the exact connector.

### 1. Host packages

Zephyr needs a handful of Ubuntu packages. Check what is missing first:

```bash
dpkg -s git cmake ninja-build gperf ccache dfu-util device-tree-compiler wget \
  python3-dev python3-venv python3-tk xz-utils file make gcc gcc-multilib \
  g++-multilib libsdl2-dev libmagic1t64 usbutils 2>&1 | grep "not installed"
```

No output means you are set. (On Ubuntu 24.04 the package is named `libmagic1t64`, and the install list below uses that name too.)
Otherwise install them (needs `sudo`; ran in a clean Ubuntu 24.04 container, not on a real WSL install; see the [test log](docs/test-log.md#clean-container-test-ubuntu-2404)):

```bash
sudo apt update
sudo apt install --no-install-recommends git cmake ninja-build gperf \
  ccache dfu-util device-tree-compiler wget python3-dev python3-venv python3-tk \
  xz-utils file make gcc gcc-multilib g++-multilib libsdl2-dev libmagic1t64 usbutils
```

`usbutils` provides `lsusb`, which you need later to check the USB board.
On ARM64 WSL, omit `gcc-multilib` and `g++-multilib` (per upstream Zephyr docs).

Check versions (Zephyr wants CMake 3.28.0+, Python 3.12+, devicetree compiler 1.4.6+;
see the [Zephyr Getting Started](https://docs.zephyrproject.org/latest/develop/getting_started/index.html) page for the current minimums):

```bash
cmake --version
python3 --version
dtc --version
```

## Zephyr setup

These are the official steps, unchanged.
Everything here was run with Zephyr pinned to v4.5.0 and an ARM-only SDK (the two optional tips below), which are not in the official guide.
The unpinned commands as written below were **not** run here, so if one differs on a newer Zephyr, trust the
[official page](https://docs.zephyrproject.org/latest/develop/getting_started/index.html) and tell us.
In this guide and in the other pages, `<ZEPHYR_DIR>` means `~/zephyrproject/zephyr`.

Disk space: the Zephyr workspace was 9.3 GB here, plus the virtual environment, SDK and builds. Check free space first with `df -h ~`.

### 1. Python virtual environment and west

```bash
python3 -m venv ~/zephyrproject/.venv
source ~/zephyrproject/.venv/bin/activate
pip install west
```

Run the `source` line again in every new terminal.

### 2. Get the Zephyr source

```bash
west init -m https://github.com/zephyrproject-rtos/zephyr ~/zephyrproject
cd ~/zephyrproject
west update
```

Optional: to get exactly the release this guide was run with, use `west init --mr v4.5.0 ~/zephyrproject` instead.

`west update` downloads a lot (the workspace was 9.3 GB on disk), so give it a few minutes.

### 3. Install Python dependencies, then export Zephyr

```bash
west packages pip --install
west zephyr-export
```

Keep this order, with the venv active. `west zephyr-export` loads Zephyr's own west commands, which import Python packages that `west packages pip --install` installs.
On a fresh machine, running it first fails with `ModuleNotFoundError: No module named 'jsonschema'` (followed by a confusing `AttributeError: 'NoneType' object has no attribute 'err'`):
see [troubleshooting](docs/troubleshooting.md#west-zephyr-export-fails-with-modulenotfounderror-no-module-named-jsonschema).

### 4. Install the Zephyr SDK

`west sdk install` picks the SDK version your Zephyr checkout needs (v4.5.0 needs SDK 1.0 or newer; older 0.17.x SDKs fail at the CMake step with `Could not find a configuration file for package "Zephyr-sdk"`).

```bash
cd ~/zephyrproject/zephyr
west sdk install
```

Optional: this downloads toolchains for every architecture (several GB). For most ADI Cortex-M parts the ARM toolchain is enough (about 250 MB):
`west sdk install --gnu-toolchains arm-zephyr-eabi`. This is what was run here.

By default it installs into `~/zephyr-sdk-<version>`, here `~/zephyr-sdk-1.0.1` (seen when run here; `-b` and `-d` change this, see `west sdk install -h`).
Nothing else needs to be set up: the build finds the SDK on its own.

### 5. Build hello_world

Find your board name:

```bash
west boards --format "{name}" | grep -i max78000
```

Build for the MAX78000FTHR's Cortex-M4 core (`<board>/<soc>/<core>`):

```bash
cd ~/zephyrproject/zephyr
west build -p always -b max78000fthr/max78000/m4 samples/hello_world
```

You should end with a memory summary (18540 bytes of flash, 7.07%, for hello_world on this board) and the file below:

```bash
ls build/zephyr/zephyr.hex
```

That is the file you will flash in the next sections. For other boards, change the board name: see [docs/boards.md](docs/boards.md).

## Connect your board to WSL

WSL cannot see USB devices on its own. [usbipd-win](https://github.com/dorssel/usbipd-win)
shares a Windows USB device with WSL. Everything in this section needs the board, so it is
**untested** here, except the detection checks in step 4, which were **probed with a board** that was already attached
(the `bind` and `attach` commands themselves were not run in that session; the usbipd flags were checked against `usbipd --help` of version 5.3.0 only).

### 1. Install usbipd-win (Windows)

In PowerShell (**untested**):

```powershell
winget install --interactive --exact dorssel.usbipd-win
```

Per Microsoft's doc, without `--interactive` winget may restart your computer immediately if drivers require it, so save your work first. Then close and reopen PowerShell so `usbipd` is on your `PATH`.

### 2. Find your board (Windows)

Plug the debug probe into your PC, then run (**untested**). Which connector depends on the board (see [Hardware you need](#hardware-you-need)):
the MAX78000FTHR's own USB port (it has an on-board DAPLink probe), or the USB cable of the external probe wired to `P9` (APARD32690),
`JH3` (MAX32655EVKIT) or `JH5` (MAX78000EVKIT). Check your board's user guide for the exact connector. A charge-only cable will not work.

```powershell
usbipd list
```

Each line under `Connected:` has a `BUSID` (like `2-4`): the USB port the device sits on.
Pick the line whose `DEVICE` looks like the debug probe (on-board or external), usually named
`CMSIS-DAP`, `DAPLink` or similar, often together with a `USB Serial Device (COMx)`.
Its `STATE` is `Not shared` at this point. The rest of this guide calls that value `<BUSID>`.
If nothing new shows up when you plug the board in, try another cable (some are charge-only) or port.

### 3. Share and attach (Windows)

Sharing is done once per device and needs PowerShell **as Administrator** (**untested**):

```powershell
usbipd bind --busid <BUSID>
```

`usbipd list` now shows `Shared`. Attaching does not need Administrator (**untested**):

```powershell
usbipd attach --wsl --busid <BUSID>
```

`--wsl` uses your default WSL distribution. To pick one, add its name: `--wsl Ubuntu-24.04`.
To list your distribution names, run `wsl -l -q`.
Keep a WSL terminal open while the device is attached.
`usbipd list` now shows `Attached`.

The attachment is lost when you unplug the board, reboot, or restart WSL, so repeat the `attach` command each time.
To re-attach automatically, leave this running in a PowerShell window instead (**untested**):

```powershell
usbipd attach --wsl --busid <BUSID> --auto-attach
```

### 4. Check it from WSL

Do this before flashing. An unattached board is the usual reason `west flash` fails.

```bash
lsusb
```

You should see a new line for the debugger. **Probed with a board** (a MAX78000-class board with an on-board DAPLink probe, already attached):

```text
Bus 001 Device 002: ID 0d28:0204 NXP ARM mbed
```

The text after the ID is the USB vendor/product string, so it depends on the probe firmware (this one is not `ARM DAPLink CMSIS-DAP`).
`udevadm info` reported the model as `DAPLink_CMSIS-DAP`. On Windows, `usbipd list` showed this probe as `0d28:0204`, with the device text
`USB Mass Storage Device, USB Serial Device (COMx), USB In...` and `STATE` `Attached`.

The serial port showed up as `/dev/ttyACM0` (sometimes `ttyUSB0`), and `dmesg` printed `cdc_acm ...: ttyACM0: USB ACM device`:

```bash
ls /dev | grep -E '^tty(ACM|USB)'
dmesg | grep -i -E 'cdc_acm|ttyACM'
```

If `dmesg` prints a permission error, use `sudo dmesg | grep -i -E 'cdc_acm|ttyACM'`.

If `lsusb` shows the probe but OpenOCD later reports an access or permission error opening it (instead of `unable to find a matching CMSIS-DAP device`),
you may need a udev rule: see [Access denied / permission error](docs/troubleshooting.md#access-denied--permission-error-opening-the-probe).
With the user in group `plugdev` and udev running, OpenOCD opened this probe as a normal user without `sudo`: the installed rules file's generic `CMSIS-DAP` product-string line matched (`udevadm test`: group `plugdev`, mode 0660). A VID:PID line is needed only if your probe's product string lacks `CMSIS-DAP`.

If you see nothing new, the board is not attached. Go back to `usbipd list` on Windows,
check that `STATE` says `Attached`, and run the `attach` command again.
With no USB device attached at all, `lsusb` prints nothing and the `ls` line prints nothing either.
If `lsusb` is still empty after `attach`, run `wsl --shutdown` and then `wsl --update` in PowerShell, reopen WSL and attach again.

## Build ADI OpenOCD

The OpenOCD that ships with the Zephyr SDK 1.0.1 has no target file for some ADI boards (`max32650`, `max32655`,
`max32657`, `max32658`, `max32665`, `max78000`, `max78002`; see the [coverage matrix](docs/boards.md#openocd-target-file-coverage) and the [affected boards table](docs/troubleshooting.md#west-flash-fails-with-fatal-error-command-exited-with-status-1)).
For `max32690` boards the file and the `allow_low_pwr_dbg` command are present there (**untested with a board**). ADI keeps its own fork with the board and flash support:
[analogdevicesinc/openocd](https://github.com/analogdevicesinc/openocd). This guide builds that fork
and points `west flash` at it.

The build and `make install` into `$HOME/.local` ran here (**built**), and that build flashed a MAX78000FTHR (**flashed**; see the [test log](docs/test-log.md)).
The `sudo make install` into `/usr/local` also ran and flashed, in a clean container. Flashing any other board is **untested**.
Behind a TLS-inspecting corporate proxy, the clone can fail on a certificate error: see [troubleshooting](docs/troubleshooting.md#server-certificate-verification-failed-behind-a-corporate-proxy).

### 1. Build dependencies

The fork's own `README` lists `make`, `libtool`, `pkg-config`, `libjim`, `autoconf` and `automake`,
plus `libusb-1.0` for USB adapters, HIDAPI for the CMSIS-DAP v1 (HID) driver and `libjaylink` for J-Link.
`texinfo` is only for the info manual: configure prints `checking for makeinfo... no`
and the build still succeeds (it just skips the docs), so it is left out.

Check what is missing (no output means you are set):

```bash
dpkg -s build-essential git autoconf automake libtool pkg-config libusb-1.0-0-dev \
  libjim-dev libjaylink-dev libhidapi-dev 2>&1 | grep "not installed"
```

Install anything missing (needs `sudo`; ran in a clean Ubuntu 24.04 container):

```bash
sudo apt install build-essential git autoconf automake libtool pkg-config \
  libusb-1.0-0-dev libjim-dev libjaylink-dev libhidapi-dev
```

The package is `libtool`; a doubled `l` (`libtooll`) does not exist in Ubuntu 24.04 (`apt-cache policy libtooll` finds nothing).

### 2. Get and build the fork

This pins tag `0.12.0-1.4.0` (the fork's default branch at the time of writing). The fork uses
submodules, so clone with `--recurse-submodules`:

```bash
git clone --recurse-submodules --branch 0.12.0-1.4.0 https://github.com/analogdevicesinc/openocd ~/adi-openocd
cd ~/adi-openocd
git rev-parse HEAD
```

`git rev-parse HEAD` should print `ad75bfb79b509634b92646b9e65b958f3ea1d8bf`.
Then pick an install prefix and build. One variable, `OPENOCD_PREFIX`, is used for the build, the install and the flash helper script:

- Recommended: `export OPENOCD_PREFIX="$HOME/.local"`. It needs no `sudo`.
- Alternative: `export OPENOCD_PREFIX=/usr/local`. It needs `sudo` for the install step (ran in a clean container; it flashed).

The variable lasts for the current shell only. Set it again in each new terminal, or add it to `~/.bashrc` once if you want (your choice):

```bash
echo 'export OPENOCD_PREFIX="$HOME/.local"' >> ~/.bashrc
```

Then build:

```bash
export OPENOCD_PREFIX="$HOME/.local"   # or: /usr/local
./bootstrap
./configure --prefix="$OPENOCD_PREFIX"
make -j"$(nproc)"
```

The default `configure` is enough: its summary reports `Analog Devices Debug Agent`,
`CMSIS-DAP v2 compliant dongle (USB bulk)`, `CMSIS-DAP v1 compliant dongle (HID)` and `SEGGER J-Link Programmer`
as `yes (auto)`. If one says `no`, a library from the list above is missing.
(The fork's `README.ADI` shows ADI's own, longer release `configure` line; you do not need it here.)

### 3. Install

Run the one that matches your `OPENOCD_PREFIX`. They are alternatives, not two steps. `make install` into `$HOME/.local` and `sudo make install` into `/usr/local` both ran here (clean container).

```bash
make install        # OPENOCD_PREFIX="$HOME/.local": no sudo
```

```bash
sudo make install   # OPENOCD_PREFIX=/usr/local: needs sudo
```

The install puts the binary in `$OPENOCD_PREFIX/bin/openocd` and the board files in `$OPENOCD_PREFIX/share/openocd/scripts`.
Check that the boards you need are there:

```bash
ls "$OPENOCD_PREFIX/share/openocd/scripts/target/max32690.cfg" \
   "$OPENOCD_PREFIX/share/openocd/scripts/target/max32655.cfg" \
   "$OPENOCD_PREFIX/share/openocd/scripts/target/max78000.cfg" \
   "$OPENOCD_PREFIX/share/openocd/scripts/interface/cmsis-dap.cfg"
```

### 4. Check which OpenOCD runs

Another `openocd` earlier on your `PATH` (for example the MSDK's `~/MaximSDK/Tools/OpenOCD`) can hide the one you just built:

```bash
which -a openocd
openocd --version
"$OPENOCD_PREFIX/bin/openocd" --version
```

The fork prints `Open On-Chip Debugger (PKGVERSION)  OpenOCD 0.12.0 (<build date>)`. Others look different:
the MSDK's says `(Analog Devices 0.12.0-1.0.0-7)` and the Zephyr SDK's says `0.12.0-01050-g91bd278a5`.
If `openocd` is not the fork, either call `"$OPENOCD_PREFIX/bin/openocd"` by its full path or put `$OPENOCD_PREFIX/bin` first in `PATH`.
`scripts/flash-adi-fork.sh` below always uses the full path, so it does not depend on `PATH`.

### Already have an OpenOCD installed? Make sure the right one runs

An older OpenOCD earlier on your `PATH` is the usual reason the wrong one runs instead of the fork (`which -a` shows the `PATH` order).
Find every installation:

```bash
which -a openocd
whereis openocd
openocd --version
```

Then pick one option. Safest first:

1. Tell `west` which OpenOCD to use for each command. This is the method this guide uses (`OPENOCD_PREFIX` as above):

   ```bash
   west flash --openocd "$OPENOCD_PREFIX/bin/openocd" --openocd-search "$OPENOCD_PREFIX/share/openocd/scripts"
   ```

2. Persistent setting in the build (**untested** by this guide). Zephyr's build writes the `OPENOCD` and `OPENOCD_DEFAULT_PATH` CMake variables into the
   build's `runners.yaml` (`cmake/flash/CMakeLists.txt`), and `west build` reads extra CMake arguments from the `build.cmake-args` west setting (`build.py`).
   So a setting like this should make `west flash` use your OpenOCD, after a pristine rebuild because the paths are written at build time:

   ```bash
   west config build.cmake-args -- "-DOPENOCD=$OPENOCD_PREFIX/bin/openocd -DOPENOCD_DEFAULT_PATH=$OPENOCD_PREFIX/share/openocd/scripts"
   west build -p always -b max78000fthr/max78000/m4 samples/hello_world
   ```

   `$OPENOCD_PREFIX` expands when you run the command, and the result is stored literally. Use an absolute path, not a variable that may be unset later.
   This changes your west configuration for every build; undo it with `west config -d build.cmake-args`.
3. A shell alias in your `~/.bashrc` or `~/.zshrc` (less clean than the options above; **untested** by this guide).
   Use your own prefix. `OPENOCD_PREFIX` must be exported in the shell where the alias runs (the single quotes defer expansion until you run it):

   ```bash
   alias wflash='west flash --openocd "$OPENOCD_PREFIX/bin/openocd" --openocd-search "$OPENOCD_PREFIX/share/openocd/scripts"'
   ```

4. Last resort for machines with an older OpenOCD installed system-wide (**untested** by this guide).
   **Warning: this modifies system directories. Prefer the options above, and back up first.** Find the old binary with `whereis openocd`,
   rename it, back up the old script directory, and copy the new scripts over it:

   ```bash
   sudo mv /usr/bin/openocd /usr/bin/openocd.old
   sudo cp -a /usr/share/openocd/scripts /usr/share/openocd/scripts.bak
   sudo cp -r "$OPENOCD_PREFIX"/share/openocd/scripts/* /usr/share/openocd/scripts/
   ```

   Adjust the paths to what `whereis` printed. The distro package's next `apt upgrade` may overwrite the copied scripts.

## Flash

Build `hello_world` as in [Build hello_world](#5-build-hello_world), attach the board as in
[Connect your board to WSL](#connect-your-board-to-wsl), then run from `~/zephyrproject/zephyr`
(with the venv active and `OPENOCD_PREFIX` set as in [Build ADI OpenOCD](#build-adi-openocd)). This command needs no extra files:

```bash
cd ~/zephyrproject/zephyr && source ~/zephyrproject/.venv/bin/activate
west flash --openocd "$OPENOCD_PREFIX/bin/openocd" --openocd-search "$OPENOCD_PREFIX/share/openocd/scripts"
```

Zephyr's board file makes OpenOCD run `init`, `targets`, `reset init`, `flash write_image erase ...zephyr.hex`,
`reset run` and `shutdown`, so on success the board is flashed and should start running the program on its own.

Plain `west flash` (without `--openocd`) uses the Zephyr SDK's own OpenOCD. It was reported not to work for these boards, and that was reproduced for the MAX78000FTHR with the board attached: the SDK 1.0.1 OpenOCD printed `Can't find target/max78000.cfg` and
`FATAL ERROR: command exited with status 1`, and nothing was flashed
([troubleshooting entry](docs/troubleshooting.md#west-flash-fails-with-fatal-error-command-exited-with-status-1)).
For other boards it is an inference from the [coverage table](docs/boards.md#openocd-target-file-coverage) of which target files each OpenOCD has.
If another OpenOCD runs instead of the fork, see [Already have an OpenOCD installed?](#already-have-an-openocd-installed-make-sure-the-right-one-runs).

**Flashed (one board, one sample):** a MAX78000FTHR was flashed with `samples/hello_world` for `max78000fthr/max78000/m4` using the
pinned fork. The `west flash --openocd` command above wrote the program, and the board printed `hello_world` over serial after an explicit `reset run` (the banner appeared twice around the `reset run`; cause not investigated).
`scripts/flash-adi-fork.sh` (default prefix `$HOME/.local`) and `scripts/flash-msdk.sh` (MSDK OpenOCD) were also observed to write (`wrote 24576 bytes`, exit 0);
a `/usr/local` install flashed too, and its serial banner was seen after a `reset run`. Running was not re-confirmed over serial for the two scripts.
Not run (**untested**): other boards, the `west config build.cmake-args` route, creating a udev rule, the usbipd `bind`/`attach` commands, and `west flash` with the MSDK's OpenOCD.

What success looked like: OpenOCD printed `SWD DPIDR 0x2ba01477`, `Cortex-M4 r0p1 processor detected`, `Examination succeed`, then
`auto erase enabled` and `wrote 24576 bytes from file <path>/zephyr.hex in 1.17s (20.5 KiB/s)` (the pattern is `wrote <N> bytes from file <path> in <time>s (<rate> KiB/s)`), then `shutdown command invoked`.
Two lines `Warn : Flash protection not supported on this device` and `Warn : [max32xxx.cpu] target was in unknown state when halt was requested` were normal here.
The messages `** Programming Started **`, `** Programming Finished **` and `** Verified OK **` come from OpenOCD's separate
`program` command (`src/flash/startup.tcl`), which Zephyr's command list above does not use, so do not expect them.
Before a board was attached, `west flash` with these flags ran the fork's `openocd`, which stopped at
`unable to find a matching CMSIS-DAP device` (**ran without a board**).

### Verify it runs

`hello_world` prints over the board's UART, which shows up in WSL as `/dev/ttyACM0` on the MAX78000FTHR (see [Check it from WSL](#4-check-it-from-wsl)).
On the test machine it was `crw-rw-rw- root dialout` (observed), so no extra permission was needed. Start the reader first, then reset the board.
The FTHR's devicetree sets the console speed to 115200 (`current-speed = <115200>`).

1. In one terminal, start the reader:

   ```bash
   stty -F /dev/ttyACM0 9600 raw -echo; stty -F /dev/ttyACM0 115200 raw -echo; cat /dev/ttyACM0
   ```

   The first `stty` forces a real baud change. With only the 115200 line the output was garbage on the test setup: `stty` seems to do nothing when the driver already reports 115200
   while the probe's UART bridge keeps another rate (cause not confirmed). See [troubleshooting](docs/troubleshooting.md#serial-output-is-garbage).

2. In a second terminal, reset the board with OpenOCD (observed to work):

   ```bash
   "$OPENOCD_PREFIX/bin/openocd" -s "$OPENOCD_PREFIX/share/openocd/scripts" \
     -c 'source [find interface/cmsis-dap.cfg]' -c 'source [find target/max78000.cfg]' \
     -c init -c 'reset run' -c shutdown
   ```

Expected output in the first terminal (observed around the `reset run`; the banner appeared twice, cause not investigated):

```text
*** Booting Zephyr OS build v4.5.0 ***
Hello World! max78000fthr/max78000/m4
```

For other boards the last line is `Hello World! <board>`. Press Ctrl+C to stop `cat`. Terminal programs and serial setup for other boards are not covered.

### Optional helper scripts

The `west flash` command above is the main path. This guide also ships two optional helper scripts: `scripts/flash-adi-fork.sh` (the same command, with a default prefix) and
`scripts/flash-msdk.sh` (for the [MSDK alternative](docs/alternative-msdk.md)). Get them by cloning this repository:

```bash
git clone https://github.com/vroque19/zephyr-adi-guide.git ~/zephyr-adi-guide
```

The scripts below use `GUIDE_DIR` for that directory:

```bash
export GUIDE_DIR="$HOME/zephyr-adi-guide"
```

Then, from `~/zephyrproject/zephyr` with the venv active:

```bash
"$GUIDE_DIR/scripts/flash-adi-fork.sh"
```

The script reads `OPENOCD_PREFIX` and defaults to `$HOME/.local` if it is unset. With `/usr/local` you must have it exported
(as above), or pass it inline: `OPENOCD_PREFIX=/usr/local "$GUIDE_DIR/scripts/flash-adi-fork.sh"`.
Extra arguments go straight to `west flash`. If `$OPENOCD_PREFIX/bin/openocd` or `$OPENOCD_PREFIX/share/openocd/scripts` is missing, or `west` is not on your `PATH`
(venv not active), the script prints a message on stderr and exits with status 1.
The script was run against a stand-in `west` (a test script, not the real tool) to check its arguments (**ran without a board**). With the board attached it also flashed the MAX78000FTHR (`wrote 24576 bytes`, exit 0; running was not re-confirmed over serial; see the [test log](docs/test-log.md)).

### Alternative: MSDK OpenOCD

To flash with the MSDK's OpenOCD instead of building the fork, see [docs/alternative-msdk.md](docs/alternative-msdk.md).
The MSDK is needed only for that alternative path and for the MSDK's `arm-none-eabi-gdb`.

If `west flash` fails, see [Troubleshooting](#troubleshooting) and [docs/troubleshooting.md](docs/troubleshooting.md).

## Using a different board

Change the Zephyr board name (`west build -b ...`). For `west flash`, the runner (the part of `west flash` that drives OpenOCD) derives the OpenOCD target file from the Zephyr board itself;
`TARGET=` is only for the MSDK script.
[docs/boards.md](docs/boards.md) has the table of boards built here, how `west flash` picks the target file, and how to find yours.

## Not covered yet

Terminal programs and serial setup for other boards are not covered.

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md) for: `west flash` fails with `FATAL ERROR: command exited with status 1`;
`Can't find target/<chip>.cfg`; `Error: unable to find a matching CMSIS-DAP device`;
`Access denied` / permission errors opening the probe; `libncurses.so.5: cannot open shared object file`; and how to check whether your OpenOCD is new enough.

## Contributing and feedback

Issues are welcome. If you flash a board, please open an issue on this repository with the board, the OpenOCD you used and what happened,
so the **untested** labels can be replaced with real results. Corrections to any step are welcome too.
`scripts/check-leaks.sh` is a maintainer tool: it scans the tracked files for personal information before a commit.

## License

MIT. Copyright (c) 2026 Vanessa Roque. See [LICENSE](LICENSE).
