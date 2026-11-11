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

Anything not run by the author is marked **untested**.

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

Check versions (Zephyr wants CMake 3.20.5+, Python 3.12+, devicetree compiler 1.4.6+):

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

Zephyr v4.5.0 needs Zephyr SDK 1.0 or newer. Older SDKs such as 0.17.x fail at
the CMake step with `Could not find a configuration file for package "Zephyr-sdk"`.

Install only the ARM toolchain, which covers the MAX32690 family and most other ADI Cortex-M parts
(about 250 MB instead of several GB):

```bash
cd ~/zephyrproject/zephyr
west sdk install -t arm-zephyr-eabi
```

It installs to `~/zephyr-sdk-1.0.1` by default. For other ADI parts with a RISC-V core,
add `-t riscv64-zephyr-elf` (**untested**).

### 5. Build hello_world

Find your board name:

```bash
west boards | grep -i apard
```

Build for the APARD32690's Cortex-M4 core (`<board>/<soc>/<core>`):

```bash
cd ~/zephyrproject/zephyr
west build -p always -b apard32690/max32690/m4 samples/hello_world
```

You should end with a memory summary (about 19 KB flash for hello_world) and the file below:

```bash
ls build/zephyr/zephyr.hex
```

That is the file you will flash in the next sections.

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
