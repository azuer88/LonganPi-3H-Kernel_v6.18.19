# LonganPi-3H-SDK

Build scripts for the LonganPi 3H (Allwinner H618, arm64) SD card image.
Tested on Ubuntu 22.04 LTS.

## Hardware status (kernel 6.18.19)

| Peripheral | Status | Notes |
|---|---|---|
| CPU | ✅ Working | 4× Cortex-A53 @ up to 1416 MHz |
| HDMI display | ✅ Working | DE33 driver; `video=HDMI-A-1:1280x720@60` in cmdline — needed if monitor is in power-save at boot, may not be required for all setups |
| HDMI audio | ✅ Working | AHUB driver (`sun50i-ahub`); appears as `card 0: HDMI Audio` |
| GPU (Mali-G31) | ✅ Working | Panfrost driver; `/dev/dri/renderD128`; 432 MHz |
| VPU (Cedrus) | ✅ Working | H.264 / HEVC hardware decode; `/dev/video0` |
| WiFi | ✅ Working | AIC8800D80 USB dongle (included on board) |
| Bluetooth | ✅ Working | AIC8800 BT via USB (`hci0`) |
| Ethernet | ✅ Working | `end0` (emac1) |
| USB host | ✅ Working | 3× USB 2.0 + 3× USB 1.1 |
| SD card | ✅ Working | Boots from SD; `mmcblk1` |
| I2C | ✅ Working | `/dev/i2c-0..2` |
| Serial console | ✅ Working | `/dev/ttyS0` at 115200 baud |
| USB OTG | ⚠️ Partial | Controller present (`musb-hdrc`); peripheral mode configured; not tested |
| PWM / fan | ✅ Working | PWM driver patched in |

## Dependencies

### With Docker (recommended)

Build the image once from the repo root:

```shell
docker build --network=host -f docker/Dockerfile -t lpi3h-build .
```

The image includes all cross-compilation tools, `mmdebstrap`, `genimage`,
`qemu-user-static`, and `e2fsprogs`. See `docker/docker-build.md` for
full usage including kernel and rootfs build commands.

Host still needs `genimage` for `mksdimg.sh`:

```shell
sudo apt install genimage
```

### Without Docker

Install all dependencies directly on the host (Ubuntu 22.04):

```shell
sudo apt update
sudo apt install \
    gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
    make bc flex bison libssl-dev libelf-dev libdw-dev \
    debhelper dpkg-dev fakeroot cpio rsync kmod lsb-release python3 \
    mmdebstrap qemu-user-static binfmt-support \
    genext2fs e2fsprogs debian-archive-keyring \
    genimage fuse2fs
```

## Configuration

Copy `.env.example` to `.env` and set the following variables before building:

| Variable         | Required | Description |
|------------------|----------|-------------|
| `MACID`          | Yes      | MAC address of the board's WiFi interface (used for hostname, SSH host keys, WiFi config). Example: `e8519ee8f1a0` |
| `USER_NAME`      | Yes      | Primary user account name |
| `USER_PASS`      | Yes      | Primary user password (SHA-512 hashed at build time) |
| `AUTHORIZED_KEY` | Yes      | SSH public key installed in the user's `authorized_keys` |
| `SSID`           | Yes      | WiFi network name |
| `PKEY`           | Yes      | WiFi WPA2 passphrase |
| `NTP_SERVER`     | No       | Custom NTP server address |
| `TIMEZONE`       | No       | Timezone (e.g. `America/Los_Angeles`) |
| `APT_PROXY`      | No       | Primary APT proxy URL; used if reachable (e.g. `http://aptcacheserver:8000`) |
| `APT_PROXY_FALLBACK` | No   | Fallback APT proxy URL; used if `APT_PROXY` is unset or unreachable |
| `NOGUI`          | No       | Set to `1` to skip desktop packages |
| `MIRROR`         | No       | Debian mirror URL (default: `http://deb.debian.org`) |
| `IMAGE_NAME`     | No       | Override output image name (default: `sdcard-$MACID`) |

## Build pipeline

The build is split into two phases:

- **Firmware + kernel** — built once, outputs reused across rootfs rebuilds.
- **Rootfs** — split into a slow base build (`mkrootfs.sh`) and a fast per-device customization (`mkcustomrootfs.sh` + `mksdimg.sh`). The base ext4 is cached; only re-run `mkrootfs.sh` when changing the package list.

```
mkatf.sh            → build/bl31.bin
mkuboot.sh          → build/u-boot-sunxi-with-spl.bin   (requires bl31.bin)
mkkernel.sh         → build/*.deb                        (kernel + headers)
mkoverlay.sh        → build/overlay.deb                  (board-specific files)
mkrootfs.sh         → build/rootfs_base.ext4             (slow: ~30–60 min)
mkcustomrootfs.sh   → build/input/rootfs.ext4            (fast: ~5 min)
mksdimg.sh          → build/images/sdcard-MACID.img.xz   (fast: ~1 min)
```

### Step 1 — ARM Trusted Firmware

```shell
bash mkatf.sh
```

Clones ARM Trusted Firmware at a pinned commit, builds `bl31.bin` for the
`sun50i_h616` platform, and copies it to `build/bl31.bin`.

Controlled by env vars: `URL`, `BRANCH`, `CROSS_COMPILE`.

Output: `build/bl31.bin`

---

### Step 2 — U-Boot

```shell
bash mkuboot.sh
```

Clones U-Boot at a pinned commit, applies patches from `uboot/*.patch` in
sorted order, builds with `longanpi_3h_defconfig` using `bl31.bin`, and
copies the result to `build/u-boot-sunxi-with-spl.bin`.

Requires: `build/bl31.bin`
Controlled by env vars: `URL`, `BRANCH`, `CROSS_COMPILE`.
Output: `build/u-boot-sunxi-with-spl.bin`

---

### Step 3 — Linux kernel

```shell
bash mkkernel.sh [--clean]
```

Builds the kernel for arm64 from the source tree at `build/linux` and
produces Debian `.deb` packages placed in `build/`. The resulting
`linux-image-*.deb` is installed into the rootfs by `custom/01_install_debs.sh`
during image customization.

The kernel source at `build/linux` is based on 6.18.19 with 58 LonganPi 3H
patches applied on top. Patch files are in `linux.new/`; see
`linux.new/STATUS.md` for details.

Options:
- `--clean` — run `make clean` before building (slower, needed after config changes)

Controlled by env vars: `LINUX_DIR`, `CROSS_COMPILE`, `JOBS`, `CONFIG`.
Output: `build/linux-image-*.deb`, `build/linux-headers-*.deb`

---

### Step 4 — Overlay package

```shell
bash mkoverlay.sh
```

Packages board-specific files (device trees, firmware, config files) into
`build/overlay.deb`, which is extracted into the rootfs by
`custom/01_install_debs.sh`.

Output: `build/overlay.deb`

---

### Step 5 — Base rootfs

```shell
bash mkrootfs.sh
```

Bootstraps a Debian bookworm arm64 rootfs using `mmdebstrap`, extracts it
into a 6 GB sparse ext4 image, and saves it as `build/rootfs_base.ext4`.
This is the slow step (~30–60 min depending on network). The result is cached
— re-run only when changing the package list.

Package groups installed:

- **BASE_PACKAGE** — system tools: openssh-server, network-manager,
  systemd-sysv, wpasupplicant, bluez, avahi-daemon, u-boot-menu,
  initramfs-tools, e2fsprogs, and a set of common utilities.
- **DESKTOP_PACKAGE** — XFCE desktop, Chromium, PulseAudio Bluetooth,
  Noto fonts (skipped when `NOGUI=1`).
- **USER_PACKAGE** — additional packages from `.env`.

The base image intentionally does not contain per-device configuration
(users, SSH host keys, WiFi credentials). Those are applied by
`mkcustomrootfs.sh`.

Output: `build/rootfs_base.ext4`

---

### Step 6 — Per-device rootfs customization

```shell
bash mkcustomrootfs.sh
```

Sparse-copies `build/rootfs_base.ext4` to `build/input/rootfs.ext4`, mounts
it (auto-escalates to root via sudo), runs all scripts in `custom/` via
`customize_rootfs.sh`, then resizes the filesystem to minimum used + 500 MB
headroom using `resize2fs -P` + `resize2fs`.

Requires: `build/rootfs_base.ext4`
Output: `build/input/rootfs.ext4`

To iterate on customization scripts without rebuilding the base rootfs:

```shell
bash mktestcustom.sh
```

This mounts an overlay (fuse-overlayfs) over the base layer, runs
`customize_rootfs.sh`, and leaves the changes visible in
`build/rootfs_upper/` without touching `rootfs_base.ext4`. Use
`--reset` to force re-extraction of the base layer.

---

### Step 7 — SD card image

```shell
bash mksdimg.sh
```

Creates the final SD card image using `genimage` with this layout:

| Region         | Offset | Content |
|----------------|--------|---------|
| U-Boot SPL+env | 8 KiB  | `u-boot-sunxi-with-spl.bin` (not in partition table) |
| rootfs (MBR p1)| 8 MiB  | `rootfs.ext4` |

A fixed MBR disk signature (`0x4c503348`) is written so the rootfs partition
always has `PARTUUID=4c503348-01`, regardless of which `mmcblkX` device the
SD card is assigned at boot. The kernel uses this PARTUUID directly without
an initramfs.

The image is compressed with `xz -7`.

Requires: `build/input/rootfs.ext4`, `build/input/u-boot-sunxi-with-spl.bin`
Output: `build/images/sdcard-MACID.img.xz`

---

## Customization scripts (`custom/`)

`customize_rootfs.sh` runs each executable script in `custom/` in filename
order, passing the rootfs mount path as `$1`. Scripts are run under `fakeroot`
when not already root.

### 01_install_debs.sh

Extracts `build/overlay.deb` and `build/linux-image-*.deb` (plus headers if
present) into the rootfs using `dpkg-deb --extract`. Skips the kernel if the
same version is already installed.

After each extraction, repairs the merged-usr `/lib → usr/lib` symlink if
`dpkg-deb --extract` replaced it with a real directory (which happens because
the kernel deb contains `./lib/modules/...` entries). Without this repair,
`/sbin/init → /lib/systemd/systemd` becomes a dangling symlink and the board
fails to boot.

### 02_user_setup.sh

Creates the primary user account using direct file manipulation (no `chroot`
required). Writes `/etc/passwd`, `/etc/shadow` (SHA-512 hashed password via
`openssl passwd -6`), `/etc/group`, and sets the root password. Adds the user
to: `dialout cdrom audio video render plugdev users netdev input sudo`. The
`render` group is required for GPU/DRI access (`/dev/dri/renderD128`). Enables
avahi workstation mode.

Requires: `USER_NAME`, `USER_PASS` in `.env`.

### 03_ssh_host_keys.sh

Pre-generates SSH host keys for the board (keyed by `MACID`) and installs them
into the rootfs. Keys are generated once into `build/host_keys/$MACID/` and
reused on subsequent builds, ensuring the host fingerprint is stable across
reflashes.

Requires: `MACID` in `.env`.

### 04_authorized_key.sh

Installs the SSH public key from `AUTHORIZED_KEY` into
`/home/$USER_NAME/.ssh/authorized_keys` with correct permissions (700/600).
UID/GID are read from the rootfs `/etc/passwd` rather than the host system.

Requires: `AUTHORIZED_KEY`, `USER_NAME` in `.env`.

### 05_update_ntp.sh

Appends `NTP=$NTP_SERVER` to `/etc/systemd/timesyncd.conf` and sets the
timezone by symlinking `/etc/localtime` to the appropriate zoneinfo file.
Skipped if `NTP_SERVER` or `TIMEZONE` are not set.

### 06_update_apt_proxy.sh

Writes `/etc/apt/apt.conf.d/02Proxy` with the `APT_PROXY` URL.
Skipped (no file written) if `APT_PROXY` is unset or unreachable.

### 07_wifi.sh

Creates a NetworkManager connection profile at
`/etc/NetworkManager/system-connections/$SSID.nmconnection` for WPA2
infrastructure mode, bound to the WiFi interface named `wlx$MACID` (the
standard Linux naming for USB WiFi with a known MAC address).

Requires: `SSID`, `PKEY`, `MACID` in `.env`.

### 08_hostname.sh

Sets the hostname to `lpi3h-XXXX` (last 4 hex digits of `MACID`) by writing
`/etc/hostname` and adding a `127.0.0.1` entry to `/etc/hosts`.

Requires: `MACID` in `.env`.

### 09_lpi3h_config.sh

Board-specific P2P/WiFi suppression:

- Writes `/etc/udev/rules.d/99-no-p2p.rules` to remove the P2P virtual
  interface created by wpa_supplicant.
- Writes `/etc/wpa_supplicant/wpa_supplicant.conf` with `p2p_disabled=1`.
- Adds a systemd drop-in for `wpa_supplicant.service` to apply the above
  config.

### 99_fix_partuuid.sh

Writes Armbian-style boot files and `/etc/default/u-boot` with the correct
`PARTUUID=4c503348-01`. Runs last to override anything `u-boot-update` may
have generated during kernel deb installation in `01_install_debs.sh`.

Files written:
- `/boot/boot.cmd` — U-Boot script source (human-readable)
- `/boot/boot.scr` — compiled with `mkimage` (what U-Boot loads)
- `/boot/armbianEnv.txt` — boot variables read by boot.cmd at runtime
- `/etc/default/u-boot` — for u-boot-update compatibility
- `/boot/extlinux/extlinux.conf` → renamed to `.bak` (U-Boot scans extlinux
  before boot.scr; removing it forces U-Boot to use boot.scr)

The fixed MBR disk signature (`0x4c503348`) is written by `mksdimg.sh`,
making `PARTUUID=4c503348-01` stable across reflashes. The kernel resolves
PARTUUID directly from the MBR without an initramfs.

Requires `mkimage` (`u-boot-tools`) on the build host — included in the
Docker image.

## Flashing

**Recommended:** Use [Raspberry Pi Imager](https://www.raspberrypi.com/software/) —
it can write `.img.xz` files directly without manual decompression. Select
"Use custom image" and point it at `build/images/sdcard-MACID.img.xz`.

Alternatively, from the command line:

```shell
# Decompress and flash to SD card (replace /dev/sdX with your card)
xz -d -c build/images/sdcard-MACID.img.xz | sudo dd of=/dev/sdX bs=4M status=progress
sudo sync
```

## Tips

### Switching between GUI and no-GUI images without rebuilding the base rootfs

`mkrootfs.sh` is slow (~30–60 min). If you want to produce both a desktop image
and a headless image, build each base rootfs once and cache them by name, then
use a symlink to select which one `mkcustomrootfs.sh` uses.

**Build and save both base images:**

```shell
# Headless base
NOGUI=1 bash mkrootfs.sh
mv build/rootfs_base.ext4 build/rootfs_base_nogui.ext4

# Desktop base
NOGUI=0 bash mkrootfs.sh
mv build/rootfs_base.ext4 build/rootfs_base_gui.ext4
```

**Switch between them with a symlink:**

```shell
cd build/

# Use headless base
ln -sf rootfs_base_nogui.ext4 rootfs_base.ext4

# Use desktop base
ln -sf rootfs_base_gui.ext4 rootfs_base.ext4
```

Then run `mkcustomrootfs.sh` and `mksdimg.sh` as normal. `mkcustomrootfs.sh`
checks for `build/rootfs_base.ext4` with `-e`, which follows symlinks, so this
works correctly. Note that `--reflink=auto` (used for the sparse copy) requires
both files to be on the same filesystem; a symlink pointing across filesystems
will still work but will fall back to a regular sparse copy.

Remember to set `NOGUI` in `.env` to match the base image you have linked —
`mkcustomrootfs.sh` reads `.env` and the image name will include a `-GUI` or
`-NOGUI` suffix accordingly (added by `mksdimg.sh`).
