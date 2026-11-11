# Zephyr on ADI boards

Get from a fresh WSL install to a flashed Analog Devices board running Zephyr.
This guide follows the official
[Zephyr Getting Started](https://docs.zephyrproject.org/latest/develop/getting_started/index.html)
and adds the parts it leaves out for ADI boards (flashing with OpenOCD).

It assumes you already have WSL with Ubuntu. Installing WSL is out of scope.
The examples use the APARD32690, but you can swap in your own board.

## Tested with

| Component | Version |
| --- | --- |
| Ubuntu (WSL) | 24.04 |
| Zephyr | v4.5.0 |
| Zephyr SDK | 1.0.1 (minimal SDK, host tools and `arm-zephyr-eabi` toolchain only) |
| west | 1.5.0 |
| Python | 3.12.3 |
| Board used | APARD32690 (`apard32690/max32690/m4`, revision D) |
| ADI OpenOCD fork | tag `0.12.0-1.4.0` (commit `ad75bfb79b509634b92646b9e65b958f3ea1d8bf`), built and installed to a scratch prefix; `openocd --version` printed `Open On-Chip Debugger (PKGVERSION)  OpenOCD 0.12.0 (<build date>)` |
| MSDK | Install the current release from ADI. No version file is shipped; the one tested had GNU Arm toolchain 10.3-2021.10 and OpenOCD "Analog Devices 0.12.0-1.0.0-7" |

The venv, `west init`, `west update`, pip install, `west zephyr-export` and the build were run from scratch in a clean shell. The SDK install was run once (a real download, with no 1.0.x SDK present) and re-run later as a no-op. Anything marked **untested** was not run.

## Prerequisites

### 1. Host packages

Zephyr needs a handful of Ubuntu packages. Check what is missing first:

```bash
dpkg -s git cmake ninja-build gperf ccache dfu-util device-tree-compiler wget \
  python3-dev python3-venv python3-tk xz-utils file make gcc gcc-multilib \
  g++-multilib libsdl2-dev libmagic1t64 2>&1 | grep "not installed"
```

No output means you are set. Otherwise install them (**untested**, needs `sudo`):

```bash
sudo apt update
sudo apt install --no-install-recommends git cmake ninja-build gperf \
  ccache dfu-util device-tree-compiler wget python3-dev python3-venv python3-tk \
  xz-utils file make gcc gcc-multilib g++-multilib libsdl2-dev libmagic1
```

Check versions (Zephyr wants CMake 3.28.0+, Python 3.12+, devicetree compiler 1.4.6+):

```bash
cmake --version
python3 --version
dtc --version
```

### 2. Maxim Microcontrollers SDK (MSDK)

You need the MSDK later for its OpenOCD binaries and ADI tooling. Install it from
the [MSDK installation instructions](https://analogdevicesinc.github.io/msdk/USERGUIDE/#installation),
accepting the default location (`~/MaximSDK`). Then check it:

```bash
ls ~/MaximSDK/Tools/OpenOCD/bin/openocd
```

## Zephyr setup

These are the official steps, with one choice made for you: Zephyr is pinned to v4.5.0.

### 1. Python virtual environment and west

```bash
python3 -m venv ~/zephyrproject/.venv
source ~/zephyrproject/.venv/bin/activate
pip install west
```

Run the `source` line again in every new terminal.

### 2. Get the Zephyr source

```bash
west init --mr v4.5.0 ~/zephyrproject
cd ~/zephyrproject
west update
```

`west update` downloads a lot (about 9 GB on disk for the workspace), so give it a few minutes.

### 3. Export Zephyr and install Python dependencies

```bash
west zephyr-export
west packages pip --install
```

### 4. Install the Zephyr SDK

Zephyr v4.5.0 needs Zephyr SDK 1.0 or newer (its `cmake/modules/FindHostTools.cmake`
asks for `Zephyr-sdk 1.0`, and `SDK_VERSION` says 1.0.1). Older SDKs such as 0.17.x
fail at the CMake step with `Could not find a configuration file for package "Zephyr-sdk"`.

Install only the ARM toolchain, which is enough for most ADI Cortex-M parts
(about 250 MB instead of several GB):

```bash
cd ~/zephyrproject/zephyr
west sdk install --gnu-toolchains arm-zephyr-eabi
```

By default it installs into `~/zephyr-sdk-<version>`, here `~/zephyr-sdk-1.0.1` (observed; `-b` and `-d` change this, see `west sdk install -h`).
Nothing else needs to be set up: the build finds the SDK on its own.

### 5. Build hello_world

Find your board name:

```bash
west boards --format "{name}" | grep -i apard
```

Build for the APARD32690's Cortex-M4 core (`<board>/<soc>/<core>`). This uses the
board's default revision (D):

```bash
cd ~/zephyrproject/zephyr
west build -p always -b apard32690/max32690/m4 samples/hello_world
```

To pin the revision explicitly, use `apard32690@D/max32690/m4` (it builds the same thing).

You should end with a memory summary (about 19 KB flash for hello_world) and the file below:

```bash
ls build/zephyr/zephyr.hex
```

That is the file you will flash in the next sections.

## Connect your board to WSL

WSL cannot see USB devices on its own. [usbipd-win](https://github.com/dorssel/usbipd-win)
shares a Windows USB device with WSL. Everything in this section needs the board, so it is
all **untested** here (the usbipd flags were checked against `usbipd --help` of version 5.3.0 only).

### 1. Install usbipd-win (Windows)

In PowerShell (**untested**):

```powershell
winget install usbipd
```

Then close and reopen PowerShell so `usbipd` is on your `PATH`.

### 2. Find your board (Windows)

Plug the board into its **debug USB port** (the one wired to the on-board debugger, not a power-only port), then run (**untested**):

```powershell
usbipd list
```

Each line under `Connected:` has a `BUSID` (like `2-4`): the USB port the device sits on.
Pick the line whose `DEVICE` looks like the on-board debugger, usually named
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

You should see a new line for the debugger (the exact text depends on your board), for example:

```text
Bus 001 Device 002: ID 0d28:0204 ARM DAPLink CMSIS-DAP
```

The serial port normally shows up as `/dev/ttyACM0` (sometimes `ttyUSB0`):

```bash
ls /dev/ttyACM* /dev/ttyUSB*
dmesg | grep -i tty
```

If `dmesg` prints a permission error, use `sudo dmesg | grep -i tty`.

If you see nothing new, the board is not attached. Go back to `usbipd list` on Windows,
check that `STATE` says `Attached`, and run the `attach` command again.
With no USB device attached at all, `lsusb` prints nothing and `ls` says `No such file or directory`.

## Build ADI OpenOCD

The OpenOCD that ships with the Zephyr SDK 1.0.1 has no target file for some ADI boards (`max32655`, `max78000`,
`max78002`, `max32650`, `max32665`; see the [coverage matrix](docs/boards.md#openocd-target-file-coverage)).
For `max32690` boards the file and the `allow_low_pwr_dbg` command are present there, so the fork was not shown to be needed
(**untested with a board**). ADI keeps its own fork with the board and flash support:
[analogdevicesinc/openocd](https://github.com/analogdevicesinc/openocd). This guide builds that fork
and points `west flash` at it.

The build, `make install` into a scratch prefix and `openocd --version` were run here. The `sudo`
install into `/usr/local` and anything that touches a board are **untested**.

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

Install anything missing (**untested**, needs `sudo`):

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
Then build. Pick the install prefix with `--prefix`:

- `/usr/local` (the default of `configure`, and the default of the flash script) needs `sudo` for the install step.
- `$HOME/.local` needs no `sudo`.

```bash
./bootstrap
./configure --prefix=/usr/local
make -j"$(nproc)"
```

The default `configure` is enough: its summary reports `Analog Devices Debug Agent`,
`CMSIS-DAP v2 compliant dongle (USB bulk)`, `CMSIS-DAP v1 compliant dongle (HID)` and `SEGGER J-Link Programmer`
as `yes (auto)`. If one says `no`, a library from the list above is missing.
(The fork's `README.ADI` shows ADI's own, longer release `configure` line; you do not need it here.)

### 3. Install

System-wide (**untested**, needs `sudo`):

```bash
sudo make install
```

Or user-local, with no `sudo` (configure with `--prefix=$HOME/.local` above instead of `/usr/local`; `make install` into a scratch prefix was run here):

```bash
make install
```

The install puts the binary in `<prefix>/bin/openocd` and the board files in `<prefix>/share/openocd/scripts`.
Check that the boards you need are there:

```bash
ls <prefix>/share/openocd/scripts/target/max32690.cfg \
   <prefix>/share/openocd/scripts/target/max32655.cfg \
   <prefix>/share/openocd/scripts/target/max78000.cfg \
   <prefix>/share/openocd/scripts/interface/cmsis-dap.cfg
```

### 4. Check which OpenOCD runs

Another `openocd` earlier on your `PATH` (for example the MSDK's `~/MaximSDK/Tools/OpenOCD`) can hide the one you just built:

```bash
which -a openocd
openocd --version
<prefix>/bin/openocd --version
```

The fork prints `Open On-Chip Debugger (PKGVERSION)  OpenOCD 0.12.0 (<build date>)`. Others look different:
the MSDK's says `(Analog Devices 0.12.0-1.0.0-7)` and the Zephyr SDK's says `0.12.0-01050-g91bd278a5`.
If `openocd` is not the fork, either call `<prefix>/bin/openocd` by its full path or put `<prefix>/bin` first in `PATH`.
`scripts/flash-adi-fork.sh` below always uses the full path, so it does not depend on `PATH`.

## Flash

Build `hello_world` as in [Build hello_world](#5-build-hello_world), attach the board as in
[Connect your board to WSL](#connect-your-board-to-wsl), then run from `~/zephyrproject/zephyr`
(with the venv active):

```bash
~/path/to/zephyr-adi-guide/scripts/flash-adi-fork.sh
```

(use wherever you cloned this guide). The script is a thin wrapper:

```bash
west flash --openocd "$OPENOCD_PREFIX/bin/openocd" --openocd-search "$OPENOCD_PREFIX/share/openocd/scripts" "$@"
```

`OPENOCD_PREFIX` defaults to `/usr/local`. If you installed to `$HOME/.local`:

```bash
OPENOCD_PREFIX=$HOME/.local ~/path/to/zephyr-adi-guide/scripts/flash-adi-fork.sh
```

Extra arguments go straight to `west flash`. If `<prefix>/bin/openocd` is missing or not executable,
the script prints a message on stderr and exits with status 1.

Zephyr's board file makes OpenOCD run `init`, `targets`, `reset init`, `flash write_image erase ...zephyr.hex`,
`reset run` and `shutdown`, so on success the board is flashed and starts running the program on its own.

The wrapper's arguments were checked here against a stub `west`, and `west flash` accepted the flags and ran the fork's
`openocd` (it stopped at `unable to find a matching CMSIS-DAP device`, as expected with no board).
**Flashing a real board was not run (untested)**, so there is no success output to paste yet.

Alternative: MSDK OpenOCD. To flash with the MSDK's OpenOCD instead of building the fork, see [docs/alternative-msdk.md](docs/alternative-msdk.md).

If `west flash` fails, see [Troubleshooting](#troubleshooting) and [docs/troubleshooting.md](docs/troubleshooting.md).

## Using a different board

Change the Zephyr board name (`west build -b ...`). For `west flash`, the runner derives the OpenOCD target file from the Zephyr board itself;
`TARGET=` is only for the MSDK script.
[docs/boards.md](docs/boards.md) has the table of boards built here, how `west flash` picks the target file, and how to find yours.

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md) for: `west flash` fails with `FATAL ERROR: command exited with status 1`;
`Can't find target/<chip>.cfg`; `Error: unable to find a matching CMSIS-DAP device`;
`libncurses.so.5: cannot open shared object file`; and how to check whether your OpenOCD is new enough.
