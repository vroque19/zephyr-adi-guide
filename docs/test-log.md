# Test log: what was run, where, and when

This page holds the details behind the status words in the [README](../README.md#zephyr-on-adi-boards). Everything was run on Ubuntu 24.04 under WSL2 on one machine,
in November 2026, with one board: a MAX78000FTHR (on-board DAPLink probe, USB `0d28:0204`). Nothing else was flashed.
The probe's serial number is not published (shown as `<serial>`).

## OpenOCD builds used

| Name in this guide | What it is | Used for |
| --- | --- | --- |
| Pinned fork build | Tag `0.12.0-1.4.0`, commit `ad75bfb79b509634b92646b9e65b958f3ea1d8bf`, built from the README steps (`./bootstrap`, `./configure --prefix=<prefix>`, `make -j"$(nproc)"`, `make install`, all exit 0) into a temporary prefix under `/tmp`. `openocd --version` printed `Open On-Chip Debugger (PKGVERSION)  OpenOCD 0.12.0 (2026-11-12-23:07)`; the text `(PKGVERSION)` is literal | Flashing the FTHR with `west flash --openocd` and with `scripts/flash-adi-fork.sh` |
| Earlier pinned build | The same tag built earlier in a different temporary prefix (`OpenOCD 0.12.0 (2026-11-12-22:58)`), since deleted | One read-only probe: `max78000.cfg` connected |
| Fork build in `/usr/local` | An earlier build installed in `/usr/local` on the test machine (`OpenOCD 0.12.0 (2026-03-11-14:25)`, no tag in its version string, not necessarily the pinned tag) | Read-only probes and the coverage matrix; not used for flashing |
| Zephyr SDK 1.0.1 | `Open On-Chip Debugger 0.12.0-01050-g91bd278a5 (2026-03-25-02:24)` | Read-only probes; plain `west flash` |
| MSDK | `Analog Devices 0.12.0-1.0.0-7` (2023-09-27) | Read-only probes; `scripts/flash-msdk.sh` |

## Board attached, read-only checks

Detection (the board was already attached; `bind` and `attach` were not run):

- `usbipd list` row for the probe: `0d28:0204  USB Mass Storage Device, USB Serial Device (COMx), USB In...  Attached`.
- `lsusb -d 0d28:0204`: `Bus 001 Device 002: ID 0d28:0204 NXP ARM mbed`; `udevadm` model: `DAPLink_CMSIS-DAP`.
- `/dev/ttyACM0` appeared; `dmesg | grep -i -E 'cdc_acm|ttyACM'` printed `cdc_acm 1-1:1.1: ttyACM0: USB ACM device` among its lines. `/dev/ttyACM0` was `crw-rw-rw- root dialout`.
- Permissions: user in `plugdev`, probe node `crw-rw---- root plugdev`, systemd and `systemd-udevd` running. The installed `60-openocd.rules` has the generic line
  `ATTRS{product}=="*CMSIS-DAP*", MODE="660", GROUP="plugdev", TAG+="uaccess"`; `udevadm test` printed `60-openocd.rules:158 GROUP 46` and `:158 MODE 0660`.
  The same generic line is in a local checkout of the fork's `contrib/60-openocd.rules` (commit `8d754a249`, not the pinned tag).

OpenOCD probes (`-s <scripts> -c 'source [find interface/cmsis-dap.cfg]' -c 'source [find target/<chip>.cfg]' -c init -c targets -c shutdown`, normal user, nothing written):
all builds that connected printed `SWD DPIDR 0x2ba01477` and `Cortex-M4 r0p1 processor detected`. Results are in the table in [docs/boards.md](boards.md#probed-with-a-board).
The `/usr/local` fork and the pinned build printed target state `unknown`; the SDK and MSDK printed `running`. This was not investigated.
`allow_low_pwr_dbg` (host-only check after loading the cfg, without `init`): present in the `/usr/local` fork and in SDK 1.0.1, absent in the MSDK.

## Flash tests (MAX78000FTHR, `samples/hello_world`, Zephyr v4.5.0)

Build: `west build -p always -b max78000fthr/max78000/m4 samples/hello_world -d <build>`: flash 18540 B (7.07%), RAM 4712 B (7.19%), `zephyr.hex` 52263 B.

| Run | Result |
| --- | --- |
| `west flash -d <build> --openocd "$OPENOCD_PREFIX/bin/openocd" --openocd-search "$OPENOCD_PREFIX/share/openocd/scripts"`, pinned fork | `SWD DPIDR 0x2ba01477`, `Cortex-M4 r0p1 processor detected`, `Examination succeed`, `Warn : [max32xxx.cpu] target was in unknown state when halt was requested`, `halted due to debug-request, current mode: Thread`, two `Warn : Flash protection not supported on this device`, `auto erase enabled`, `wrote 24576 bytes from file <build>/zephyr/zephyr.hex in 1.172077s (20.476 KiB/s)`, a second `SWD DPIDR 0x2ba01477`, `shutdown command invoked` |
| Serial check after that flash | Reader started (`stty -F /dev/ttyACM0 115200 raw -echo; cat /dev/ttyACM0`; later runs needed a baud toggle, see the container section), then `openocd ... -c init -c 'reset run' -c shutdown`: `*** Booting Zephyr OS build v4.5.0 ***` and `Hello World! max78000fthr/max78000/m4`, twice around the `reset run` (cause not investigated; the reader was started before the reset) |
| `scripts/flash-adi-fork.sh` (prefix under `/tmp`, `-d <build>`) | `-- west flash: using runner openocd`, `wrote 24576 bytes ... in 1.166665s (20.571 KiB/s)`, exit 0. Running was not re-confirmed over serial |
| `TARGET=max78000 scripts/flash-msdk.sh <build>/zephyr/zephyr.hex` (MSDK OpenOCD) | `wrote 24576 bytes ... in 1.017537s (23.586 KiB/s)`, `shutdown command invoked`. Running was not re-confirmed over serial |
| Plain `west flash -d <build>` (SDK 1.0.1 OpenOCD pinned in `runners.yaml`) | `-- west flash: rebuilding`, `ninja: no work to do.`, `-- west flash: using runner openocd`, `Flashing file: <build>/zephyr/zephyr.hex`, the SDK banner, `Can't find target/max78000.cfg`, `FATAL ERROR: command exited with status 1: ...`. No `openocd.log` was created; nothing was flashed |

The devicetree speed `current-speed = <115200>` was read from `boards/adi/max78000fthr/max78000fthr.dtsi` (lines 82 and 111).

## Ran without a board (earlier)

`west flash` for the APARD32690 and for a MAX78000 board with the SDK's OpenOCD and with the `/usr/local` fork; `scripts/flash-adi-fork.sh` against a stand-in `west`;
`scripts/flash-msdk.sh` with a dummy hex file. They stopped at `unable to find a matching CMSIS-DAP device` or `Can't find target/<chip>.cfg`, as described in [troubleshooting](troubleshooting.md).

## Clean container test (Ubuntu 24.04)

A fresh Ubuntu 24.04 container with only `python3`, `curl`, `wget` and `ca-certificates` preinstalled, passwordless `sudo` and a user in the usual WSL groups.
The repository's published files were exported into it with `git archive`. This is not a real WSL install and has no board. What was run so far:

- The host packages from [Prerequisites](../README.md#1-host-packages) (`sudo apt update && sudo apt install ...`): exit 0 (CMake 3.28.3, Python 3.12.3, DTC 1.7.0). This ran in a clean container.
- `west init` and `west update` of v4.5.0: worked on the second attempt (the first attempt hit a network DNS failure, unrelated to the guide).
- `west zephyr-export` before `west packages pip --install`: **failed** with `ModuleNotFoundError: No module named 'jsonschema'`, then `AttributeError: 'NoneType' object has no attribute 'err'`.
  This was a bug in the guide's order; it is fixed (the README now installs the Python packages first). It had gone unnoticed because the packages were already installed on the first test machine.
- With the corrected order (`west packages pip --install`, `west zephyr-export`), `west sdk install --gnu-toolchains arm-zephyr-eabi` and
  `west build -p always -b max78000fthr/max78000/m4 samples/hello_world` all exited 0: flash 18540 B, RAM 4712 B, `zephyr.hex` 52263 B, the same as the host build.

### Container steps a) to g)

Clean Ubuntu 24.04 Docker container, user in `sudo`, `plugdev` and `dialout`, board passed through from a WSL2 host. README commands were run verbatim unless noted. Two deviations were forced by a TLS-inspecting corporate proxy: the clone and the `.deb` downloads were done on the host and copied in.

| Step | Command (as run) | Result |
| --- | --- | --- |
| a) Quick start step 4 | `apt install` of the build dependencies; clone of the fork (host clone of commit `ad75bfb79b509634b92646b9e65b958f3ea1d8bf` copied in, because `git clone --recurse-submodules` failed on a certificate error); `./bootstrap`, `./configure --prefix="$HOME/.local"`, `make -j"$(nproc)"`, `make install` | All succeeded. `OpenOCD 0.12.0 (2026-11-13-16:36)` with the literal `(PKGVERSION)`; CMSIS-DAP v1 and v2, J-Link and ADI Debug Agent all `yes (auto)` |
| b) Quick start step 5 | `west flash --openocd "$OPENOCD_PREFIX/bin/openocd" --openocd-search "$OPENOCD_PREFIX/share/openocd/scripts"` with `OPENOCD_PREFIX=$HOME/.local` | Exit 0; `auto erase enabled`; `wrote 24576 bytes ... in 1.229490s (19.520 KiB/s)`; the same two `Warn : Flash protection not supported on this device` lines |
| c) Helper script | `scripts/flash-adi-fork.sh` (default prefix `$HOME/.local`) | Exit 0; `wrote 24576 bytes ... in 1.266373s` |
| d) `/usr/local` | `./bootstrap`, `./configure --prefix=/usr/local`, `make -j`, `sudo make install`, then `west flash --openocd /usr/local/bin/openocd ...` | All exit 0; wrote 24576 bytes; the serial banner was seen after a `reset run` |
| e) Plain `west flash` | No flags (SDK 1.0.1 OpenOCD pinned in `runners.yaml`) | Exit 1; `Can't find target/max78000.cfg` and `FATAL ERROR: command exited with status 1`; no `build/openocd.log`. Same as on the host |
| f) MSDK path | MSDK mounted read-only from the host. `~/MaximSDK/Tools/GNUTools/10.3/bin/arm-none-eabi-gdb --version`; then `sudo apt install ./libtinfo5_6.3-2ubuntu0.3_amd64.deb ./libncurses5_6.3-2ubuntu0.3_amd64.deb` (downloaded on the host from the same https URLs); then `TARGET=max78000 scripts/flash-msdk.sh` | gdb first failed with `error while loading shared libraries: libncurses.so.5: cannot open shared object file`; after the install it printed `GNU gdb (GNU Arm Embedded Toolchain 10.3-2021.10) 10.2.90.20210621-git`. The script exited 0 and wrote 24576 bytes in 1.000938s (23.978 KiB/s) |
| g) Serial | `stty -F /dev/ttyACM0 115200 raw -echo; cat /dev/ttyACM0` after flashing | Garbage bytes (like `dc d9 98 64 fe ...`) in three attempts, from the container and the host, although `stty -a` reported 115200. After `stty -F /dev/ttyACM0 9600 raw -echo; stty -F /dev/ttyACM0 115200 raw -echo` and a `reset run`, the output was correct (`*** Booting Zephyr OS build v4.5.0 ***` / `Hello World! max78000fthr/max78000/m4`, the banner printed twice around the `reset run`). Cause not confirmed |

Observed on a TLS-inspecting proxy only inside Docker: `server certificate verification failed` from git (submodule from `gitlab.zapb.de`) and `cannot verify security.ubuntu.com's certificate ... Self-signed certificate encountered` from wget. The same URLs worked from the WSL distribution.

## Not run

Other boards (APARD32690, MAX78000EVKIT, MAX32655EVKIT, and every `max32690` or `max32655` flash), `sudo` installs on a real WSL install (they ran only in a clean container) and `/etc/udev/rules.d` changes, the `west config build.cmake-args` route,
the usbipd `bind` and `attach` commands, `west flash` with the MSDK's OpenOCD, creating a udev rule, and any other sample than `hello_world`.
