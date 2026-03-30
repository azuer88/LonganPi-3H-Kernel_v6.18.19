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
10. `99_fix_partuuid.sh` — writes `/boot/extlinux/extlinux.conf` (reference copy) and `/etc/default/u-boot` with correct PARTUUID (`4c503348-02`); removes Armbian-style boot files if present

### Partition layout and PARTUUID
The MBR disk signature is hardcoded to `0x4c503348` in `mksdimg.sh`. The SD card has two partitions:
- **Partition 1** (FAT32, offset 1M, size 63M): boot partition — `PARTUUID=4c503348-01`. Contains `vmlinuz-*`, DTB, and `extlinux/extlinux.conf`. U-Boot reads from here via its FAT driver (avoids the ext4 block-group > 3 inode-table read limitation).
- **Partition 2** (ext4, offset 64M): rootfs — `PARTUUID=4c503348-02`. Used as `root=` in kernel cmdline.

`mkcustomrootfs.sh` creates `build/input/boot.fat` (the authoritative boot config). `99_fix_partuuid.sh` writes a matching `extlinux.conf` to `$ROOTFS/boot/extlinux/extlinux.conf` for reference only — U-Boot does **not** read that copy. **Do not change this signature** without updating both scripts — the kernel boots without an initramfs and resolves root directly from PARTUUID.

### Build environment constraints
- `mkcustomrootfs.sh` must run on the **host** (not in Docker) — needs root for `mount`, `mkfs.fat`, `mcopy`
- `uuidgen` is **not** in the `lpi3h-build` Docker image; `07_wifi.sh` falls back to `/proc/sys/kernel/random/uuid`
- `build/uboot/` is owned by root (created inside Docker); edit via `docker run --rm -v /extra/LPI3H/LonganPi-3H-SDK:/sdk lpi3h-build bash -c "..."`

### firstboot.sh behaviour
- Runs **once** on first boot via `firstboot.service`; renamed to `/opt/firstboot.sh.done` afterward (never reruns)
- To manually resize rootfs on a running board: `parted /dev/mmcblk0 resizepart 2 100%` then `resize2fs /dev/mmcblk0p2` (online resize is safe)

### Serial console interaction
- Use Python `pyserial` for scripted serial interaction when board has no SSH yet
- `sudo -S` with heredoc password works over SSH: `sudo -S cmd <<< password`

### Kernel source (`build/linux`)
- Base: Linux 6.18.19 (commit `4aea1dc4c`)
- 59 patches applied; current HEAD: `930f33032` (pending 0059 commit)
- Patch files: `kernel_patches/0001-*.patch` … `0059-*.patch`
- Full apply history: `kernel_patches/STATUS.md`
- Config: `arch/arm64/configs/longanpi_3h_defconfig`
- To revert all patches: `cd build/linux && git reset --hard 4aea1dc4c`

Notable patches:
- `0048` — H616/DE33 display (ported to 6.18 API); required for HDMI output
- `0050` — Cedrus H264/HEVC hardware VPU (H616 SRAM C1 mapping)
- `0054` — cedrus/dts: fix H616 VE GIC interrupt SPI 89→93; restore upstream watchdog
- `0055` — dts: constrain CMA pool below 4 GB (sun4i DMA_BIT_MASK(32) fix for HDMI display)
- `0056` — defconfig: add HDMI I2S audio drivers
- `0059` — defconfig: enable USB serial subsystem + CH341 driver (`/dev/ttyUSB*`)

### U-Boot source (`build/uboot`)
- Cloned and patched by `mkuboot.sh` on first run (base: `da2e3196e`)
- 13 patches in `uboot/0001-*.patch` … `uboot/0013-*.patch` (upstream sipeed + local fixes)
- Must be built in Docker (same `lpi3h-build` image as kernel)
- Output: `build/u-boot-sunxi-with-spl.bin` — flash raw to SD: `dd if=... of=/dev/mmcblkX bs=1024 seek=8`

### Board-specific notes (lpi3h-f1a0)
- Serial console: `/dev/ttyUSB0` at 115200 baud
- SSH: `lpi3h-f1a0` (mDNS) or IP from router; user `default`, password from `USER_PASS` in `.env`
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
