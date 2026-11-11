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

## Troubleshooting

### `libncurses.so.5: cannot open shared object file` (or `libtinfo.so.5`)

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
