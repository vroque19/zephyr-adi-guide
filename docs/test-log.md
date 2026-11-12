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
| Serial check after that flash | Reader started (`stty -F /dev/ttyACM0 115200 raw -echo; cat /dev/ttyACM0`), then `openocd ... -c init -c 'reset run' -c shutdown`: `*** Booting Zephyr OS build v4.5.0 ***` and `Hello World! max78000fthr/max78000/m4`, twice (the boot after the flash, then the reset) |
| `scripts/flash-adi-fork.sh` (prefix under `/tmp`, `-d <build>`) | `-- west flash: using runner openocd`, `wrote 24576 bytes ... in 1.166665s (20.571 KiB/s)`, exit 0. Running was not re-confirmed over serial |
| `TARGET=max78000 scripts/flash-msdk.sh <build>/zephyr/zephyr.hex` (MSDK OpenOCD) | `wrote 24576 bytes ... in 1.017537s (23.586 KiB/s)`, `shutdown command invoked`. Running was not re-confirmed over serial |
| Plain `west flash -d <build>` (SDK 1.0.1 OpenOCD pinned in `runners.yaml`) | `-- west flash: rebuilding`, `ninja: no work to do.`, `-- west flash: using runner openocd`, `Flashing file: <build>/zephyr/zephyr.hex`, the SDK banner, `Can't find target/max78000.cfg`, `FATAL ERROR: command exited with status 1: ...`. No `openocd.log` was created; nothing was flashed |

The devicetree speed `current-speed = <115200>` was read from `boards/adi/max78000fthr/max78000fthr.dtsi` (lines 82 and 111).

## Ran without a board (earlier)

`west flash` for the APARD32690 and for a MAX78000 board with the SDK's OpenOCD and with the `/usr/local` fork; `scripts/flash-adi-fork.sh` against a stand-in `west`;
`scripts/flash-msdk.sh` with a dummy hex file. They stopped at `unable to find a matching CMSIS-DAP device` or `Can't find target/<chip>.cfg`, as described in [troubleshooting](troubleshooting.md).

## Not run

Other boards (APARD32690, MAX78000EVKIT, MAX32655EVKIT, and every `max32690` or `max32655` flash), `sudo` installs (host packages, `/usr/local` OpenOCD, `/etc/udev/rules.d` changes), the `west config build.cmake-args` route,
the usbipd `bind` and `attach` commands, `west flash` with the MSDK's OpenOCD, and any other sample than `hello_world`.
