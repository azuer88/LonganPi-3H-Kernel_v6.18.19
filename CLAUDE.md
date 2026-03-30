# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Build system for a customized Debian bookworm arm64 SD card image for the LonganPi 3H (Allwinner H618 SoC, Mali-G31 GPU). All scripts run on an x86 cross-build host (`longan-builder`); the resulting image is flashed to the board (`lpi3h-f1a0`).

## Key commands

### Build the kernel (most common task)
```bash
bash mkkernel.sh           # incremental build
bash mkkernel.sh --clean   # clean build (after config changes)
```
The kernel source at `build/linux` is pre-patched (51 commits on 6.18.19). Outputs `build/*.deb`.

### Iterate on rootfs customization scripts (fast, no rebuild)
```bash
bash mktestcustom.sh           # overlay run — changes visible in build/rootfs_upper/
bash mktestcustom.sh --reset   # force re-extract base layer from rootfs_base.ext4
```

### Full image build (from scratch)
```bash
bash mkatf.sh             # ARM Trusted Firmware → build/bl31.bin
bash mkuboot.sh           # U-Boot → build/u-boot-sunxi-with-spl.bin
bash mkkernel.sh          # kernel .debs → build/
bash mkoverlay.sh         # board overlay .deb → build/
bash mkrootfs.sh          # base rootfs → build/rootfs_base.ext4  (slow, ~30-60 min)
bash mkcustomrootfs.sh    # per-device customization → build/input/rootfs.ext4
bash mksdimg.sh           # SD image → build/images/sdcard-$MACID.img.xz
```

### Install updated kernel to a running board
```bash
# Copy the .deb, install it, fix extlinux if needed
scp build/linux-image-*.deb lpi3h-f1a0:
ssh lpi3h-f1a0 'sudo dpkg -i linux-image-*.deb'
```

## Configuration

Requires a `.env` file (no `.env.example` exists — create from this list):

```
MACID=e8519ee8f1a0        # board WiFi MAC, used for hostname/SSH keys/WiFi config
USER_NAME=default
USER_PASS=yourpassword    # plaintext; hashed with openssl passwd -6 at build time
AUTHORIZED_KEY=<pubkey>
SSID=mywifi
PKEY=wpapassphrase
TIMEZONE=America/Los_Angeles
NTP_SERVER=192.168.1.1
APT_PROXY=http://192.168.254.81:8080   # optional; mkrootfs.sh uses if reachable, else tries APT_PROXY_FALLBACK
APT_PROXY_FALLBACK=http://localhost:8080  # optional; mkrootfs.sh fallback only — 06_update_apt_proxy.sh ignores this
NOGUI=0                   # set 1 to skip XFCE desktop
IMAGE_NAME=sdcard-$MACID  # optional override
```

## Architecture

### Build flow
```
mkatf.sh → bl31.bin
mkuboot.sh (uses bl31.bin) → u-boot-sunxi-with-spl.bin
mklinux.sh → build/linux/  [clone Linux 6.18.19 + apply kernel_patches/; skips if exists]
mkkernel.sh → linux-image-*.deb, linux-headers-*.deb
mkoverlay.sh → overlay.deb (board config/firmware, package: sipeed-longanpi3h-extra)
mkrootfs.sh → build/rootfs_base.ext4  [slow, cached, re-run only for package changes]
mkcustomrootfs.sh → build/input/rootfs.ext4  [fast, per-device, re-run freely]
mksdimg.sh → build/images/sdcard-MACID.img.xz
```

### Customization script pipeline
`customize_rootfs.sh` runs `custom/NN_*.sh` in order, each receiving the rootfs mount path as `$1`. Scripts run under `fakeroot` when not root. Order matters:

1. `01_install_debs.sh` — extracts `overlay.deb` + `linux-image-*.deb` into rootfs; repairs `/lib → usr/lib` symlink that `dpkg-deb --extract` can overwrite (breaks systemd boot if not repaired)
2. `02_user_setup.sh` — creates user, sets user password from `USER_PASS` (hashed at build time); sets root password to a random 256-bit value (effectively locked); writes directly to `/etc/passwd`, `/etc/shadow`, `/etc/group` (no chroot)
3. `03_ssh_host_keys.sh` — pre-generates SSH host keys keyed by `MACID`; cached in `build/host_keys/$MACID/` for stable fingerprints across reflashes
4. `04_authorized_key.sh` — installs SSH pubkey; reads UID/GID from rootfs `/etc/passwd`
5. `05_ntp.sh` — NTP/timezone config
6. `06_update_apt_proxy.sh` — writes `/etc/apt/apt.conf.d/02Proxy` if `APT_PROXY` is set and reachable; no fallback
7. `07_wifi.sh` — NetworkManager profile for `wlx$MACID` interface (USB WiFi naming)
8. `08_hostname.sh` — sets `lpi3h-XXXX` (last 4 hex of MACID)
9. `09_lpi3h_config.sh` — udev rule to suppress P2P WiFi interface
10. `99_fix_partuuid.sh` — writes `/boot/extlinux/extlinux.conf` and `/etc/default/u-boot` with correct PARTUUID; removes Armbian-style boot files if present

### Partition layout and PARTUUID
The MBR disk signature is hardcoded to `0x4c503348` in `mksdimg.sh`, making the rootfs partition always `PARTUUID=4c503348-01`. This PARTUUID is used in `extlinux.conf` (written by `99_fix_partuuid.sh`). **Do not change this signature** without updating that script — the kernel boots without an initramfs and resolves root directly from PARTUUID.

### Kernel source (`build/linux`)
- Base: Linux 6.18.19 (commit `4aea1dc4c`)
- 58 patches applied; current HEAD: `930f33032`
- Patch files: `kernel_patches/0001-*.patch` … `0058-*.patch`
- Full apply history: `kernel_patches/STATUS.md`
- Config: `arch/arm64/configs/longanpi_3h_defconfig`
- To revert all patches: `cd build/linux && git reset --hard 4aea1dc4c`

Notable patches:
- `0048` — H616/DE33 display (ported to 6.18 API); required for HDMI output
- `0050` — Cedrus H264/HEVC hardware VPU (H616 SRAM C1 mapping)
- `0054` — cedrus/dts: fix H616 VE GIC interrupt SPI 89→93; restore upstream watchdog
- `0055` — dts: constrain CMA pool below 4 GB (sun4i DMA_BIT_MASK(32) fix for HDMI display)
- `0056` — defconfig: add HDMI I2S audio drivers

### Board-specific notes (lpi3h-f1a0)
- Serial console: `/dev/ttyUSB0` at 115200 baud
- extlinux: two entries — `l0` = `6.18.19+` (old), `l1` = `6.18.19` (current patched). Default: `l1`
- HDMI requires `video=HDMI-A-1:1280x720@60` in kernel cmdline; without it, display fails if monitor is in power-save at boot
- Panfrost (Mali-G31) works at 432 MHz; requires `CONFIG_SUN50I_H6_PRCM_PPU=y` for GPU power domain

### `bsp/` directory
Out-of-tree kernel module support files (drivers, headers, Kconfig, Makefile) — included in the kernel build via `mklinux.sh`-era `cp -raf bsp build/linux`. Already present in the patched tree.

### `overlay/` directory
Source for `overlay.deb` (`sipeed-longanpi3h-extra`). Contains:
- `etc/` — board config files installed into rootfs
- `opt/firstboot.sh` — first-boot script
- `usr/` — additional userspace files
- `DEBIAN/control` — package metadata
