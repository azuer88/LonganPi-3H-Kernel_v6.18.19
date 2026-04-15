# LonganPi-3H-SDK

Build scripts for the LonganPi 3H (Allwinner H618, arm64) SD card image.
Tested on Ubuntu 22.04 LTS.

Testing trixie resulted in slower video decode, for some reason.  Haven't gotten to dig deeper.

Based on [sipeed/LonganPi-3H-SDK](https://github.com/sipeed/LonganPi-3H-SDK).

## Hardware status (kernel 6.18.19)

| Peripheral | Status | Notes |
|---|---|---|
| CPU | ✅ Working | 4× Cortex-A53 @ up to 1416 MHz |
| HDMI display | ✅ Working | DE33 driver; `video=HDMI-A-1:1280x720@60` in cmdline — needed if monitor is in power-save at boot, may not be required for all setups |
| HDMI audio | ✅ Working | AHUB driver (`sun50i-ahub`); appears as `card 0: HDMI Audio` |
| GPU (Mali-G31) | ✅ Working | Panfrost driver; `/dev/dri/renderD128`; 432 MHz; OpenGL ES 3.1; glmark2 score 206 @ 1920×1080 |
| VPU (Cedrus) | ✅ Working | H.264 / HEVC hardware decode; `/dev/video0` |
| WiFi | ✅ Working | AIC8800D80 USB dongle (included on board) |
| Bluetooth | ✅ Working | AIC8800 BT via USB (`hci0`) |
| Ethernet | ✅ Working | `end0` (emac1) |
| USB host | ✅ Working | 3× USB 2.0 + 3× USB 1.1 |
| SD card | ✅ Working | Boots from SD; `mmcblk1` |
| I2C | ✅ Working | `/dev/i2c-0..2` |
| SPI | ✅ Working | `spi_sun6i` on SPI1 (PH5–PH8 header pins); `/dev/spidev1.0` via `rohm,dh2228fv` spidev node |
| Serial console | ✅ Working | `/dev/ttyS0` at 115200 baud |
| USB OTG | ✅ Working | `musb-hdrc`; peripheral mode; ACM serial (`/dev/ttyGS0` ↔ host `/dev/ttyACM0`) and RNDIS (USB Ethernet) tested |
| USB serial (CH340/CH341) | ✅ Working | `/dev/ttyUSB*`; `CONFIG_USB_SERIAL_CH341=m` |
| PWM / fan | ✅ Working | PWM driver patched in |

## Dependencies

### With Docker (recommended)

Build the image once from the repo root:

```shell
docker build --network=host -f docker/Dockerfile -t lpi3h-build .
```

The image includes all cross-compilation tools, `mmdebstrap`,
`qemu-user-static`, and `e2fsprogs`. See [`docs/docker-build.md`](docs/docker-build.md) for
full usage. Use `run_docker.sh` as a convenience wrapper:

```shell
run_docker.sh mkkernel.sh
run_docker.sh mkuboot.sh
```

`mkrootfs.sh` requires loop-device access inside the container for `mmdebstrap`
to mount its ext2 image. Pass `--privileged` for that script only:

```shell
run_docker.sh --privileged mkrootfs.sh
```

Other scripts (`mkkernel.sh`, `mkuboot.sh`) do not need `--privileged`.

Host still needs `genimage` for `mksdimg.sh` (not in Ubuntu 22.04 repos — build from source):

```shell
sudo apt install libconfuse-dev libarchive-dev pkg-config autoconf automake libtool
git clone --depth 1 https://github.com/pengutronix/genimage.git /tmp/genimage
cd /tmp/genimage && autoreconf -is && ./configure && make && sudo make install
```

### Without Docker

Install all dependencies directly on the host (Ubuntu 22.04):

```shell
sudo apt update
sudo apt install \
    gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
    make bc flex bison libssl-dev libelf-dev libdw-dev \
    debhelper dpkg-dev fakeroot cpio rsync kmod lsb-release \
    python3 python3-dev python3-setuptools swig \
    git \
    mmdebstrap qemu-user-static binfmt-support \
    genext2fs e2fsprogs debian-archive-keyring \
    fuse2fs
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
| `CODENAME`       | No       | Debian release codename (e.g. `trixie`, `bookworm`). When set, output files get a `-${CODENAME}` suffix so multiple bases can coexist in `build/` |
| `NOPASS_SUDO`    | No       | Set to `1` to install a passwordless `sudo` rule for `USER_NAME` via `/etc/sudoers.d/` |
| `MIRROR`         | No       | Debian mirror URL (default: `http://deb.debian.org`) |
| `IMAGE_NAME`     | No       | Override output image name (default: `sdcard-$MACID[-${CODENAME}]`) |

## Build pipeline

The build is split into two phases:

- **Firmware + kernel** — built once, outputs reused across rootfs rebuilds.
- **Rootfs** — split into a slow base build (`mkrootfs.sh`) and a fast per-device customization (`mkcustomrootfs.sh` + `mksdimg.sh`). The base ext4 is cached; only re-run `mkrootfs.sh` when changing the package list.

```
mkatf.sh            → build/bl31.bin
mkuboot.sh          → build/u-boot-sunxi-with-spl.bin
mklinux.sh          → build/linux/
mkkernel.sh         → build/*.deb
mkoverlay.sh        → build/overlay.deb
mkrootfs.sh         → build/rootfs_base[-CODENAME].ext4  (slow: ~30–60 min)
mkcustomrootfs.sh   → build/input/rootfs[-CODENAME].ext4
mksdimg.sh          → build/images/sdcard-MACID[-CODENAME].img.xz
```

### Step 1 — ARM Trusted Firmware

```shell
mkatf.sh
```

Clones ARM Trusted Firmware at a pinned commit, builds `bl31.bin` for the
`sun50i_h616` platform, and copies it to `build/bl31.bin`.

Controlled by env vars: `URL`, `BRANCH`, `CROSS_COMPILE`.

Output: `build/bl31.bin`

---

### Step 2 — U-Boot

```shell
run_docker.sh mkuboot.sh
```

Clones U-Boot at a pinned commit, applies patches from `uboot/*.patch` in
sorted order, builds with `longanpi_3h_defconfig` using `bl31.bin`, and
copies the result to `build/u-boot-sunxi-with-spl.bin`.

Requires: `build/bl31.bin`
Controlled by env vars: `URL`, `BRANCH`, `CROSS_COMPILE`.
Output: `build/u-boot-sunxi-with-spl.bin`

---

### Step 3 — Linux kernel source

```shell
mklinux.sh
```

Shallow-clones Linux 6.18.19 from `torvalds/linux` and applies all 62 LonganPi 3H
patches from `kernel_patches/` in order, producing `build/linux`. Skips silently
if `build/linux` already exists; use `--force` to re-clone from scratch.

Patch files and full apply history: `kernel_patches/STATUS.md`.

Controlled by env vars: `LINUX_DIR`, `LINUX_URL`, `PATCHES_DIR`, `BASE_COMMIT`, `BASE_TAG`.
Output: `build/linux/`

---

### Step 4 — Linux kernel build

```shell
run_docker.sh mkkernel.sh [--clean]
```

Builds the kernel for arm64 from the source tree at `build/linux` and
produces Debian `.deb` packages placed in `build/`. The resulting
`linux-image-*.deb` is installed into the rootfs by `custom/01_install_debs.sh`
during image customization.

Options:
- `--clean` — run `make clean` before building (slower, needed after config changes)

Controlled by env vars: `LINUX_DIR`, `CROSS_COMPILE`, `JOBS`, `CONFIG`.
Output: `build/linux-image-*.deb`, `build/linux-headers-*.deb`

After each build, `mkkernel.sh` automatically removes the `.buildinfo` and `.changes` metadata files generated by `bindeb-pkg`, and prunes older `.deb` sets so that only the two most recent build versions are retained.

---

### Step 5 — Overlay package

```shell
mkoverlay.sh
```

Packages board-specific files (device trees, firmware, config files) into
`build/overlay.deb`, which is extracted into the rootfs by
`custom/01_install_debs.sh`.

Output: `build/overlay.deb`

---

### Step 6 — Base rootfs

```shell
run_docker.sh --privileged mkrootfs.sh
```

Bootstraps a Debian arm64 rootfs using `mmdebstrap` and saves it as
`build/rootfs_base.ext4` (or `build/rootfs_base-${CODENAME}.ext4` when
`CODENAME` is set in `.env`). This is the slow step (~30–60 min depending on
network). The result is cached — re-run only when changing the package list.

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

### Step 7 — Per-device rootfs customization

```shell
mkcustomrootfs.sh
```

Sparse-copies the base ext4 to `build/input/rootfs[-CODENAME].ext4`, pre-expands
it by 1 GB to ensure room for kernel deb extraction, mounts it (auto-escalates
to root via sudo), runs all scripts in `custom/` via `customize_rootfs.sh`,
creates `build/input/boot.fat` (63 MB FAT32 image containing the kernel, DTB,
and `extlinux/extlinux.conf`), then shrinks the rootfs to minimum used + 500 MB
headroom.

**Must run on the host** — requires root for `mount`, `mkfs.fat`, and `mcopy`.
Do not run inside Docker.

Requires: `build/rootfs_base[-CODENAME].ext4`
Output: `build/input/rootfs[-CODENAME].ext4`

To iterate on customization scripts without rebuilding the base rootfs:

```shell
mktestcustom.sh
```

This mounts an overlay (fuse-overlayfs) over the base layer, runs
`customize_rootfs.sh`, and leaves the changes visible in
`build/rootfs_upper/` without touching `rootfs_base.ext4`. Use
`--reset` to force re-extraction of the base layer.

---

### Step 8 — SD card image

```shell
mksdimg.sh
```

Creates the final SD card image using `genimage` with this layout:

| Region              | Offset  | Content |
|---------------------|---------|---------|
| U-Boot SPL+env      | 8 KiB   | `u-boot-sunxi-with-spl.bin` (not in partition table) |
| Boot FAT32 (MBR p1) | 1 MiB   | `boot.fat` — vmlinuz, DTB, `extlinux/extlinux.conf`; `PARTUUID=4c503348-01` |
| rootfs ext4 (MBR p2)| 64 MiB  | `rootfs[-CODENAME].ext4`; `PARTUUID=4c503348-02` |

A fixed MBR disk signature (`0x4c503348`) is written so PARTUUIDs are stable
across reflashes regardless of `mmcblkX` device assignment. The FAT boot
partition is used because U-Boot's ext4 driver cannot read inode tables in
block groups beyond ~3 — on the rootfs filesystem (512 inodes/group), boot
files land in group 10+ and are silently unreadable. U-Boot's FAT driver has
no such limitation. The kernel resolves `root=PARTUUID=4c503348-02` directly
without an initramfs.

The image is compressed with `xz -7`.

Requires: `build/input/rootfs.ext4`, `build/input/boot.fat`, `build/input/u-boot-sunxi-with-spl.bin`
Output: `build/images/sdcard-MACID.img.xz`

---

## Customization scripts (`custom/`)

`customize_rootfs.sh` runs each executable script in `custom/` in filename
order, passing the rootfs mount path as `$1`. Scripts are run under `fakeroot`
when not already root.

### 01_install_debs.sh

Extracts `build/overlay.deb` and `build/linux-image-*.deb` (plus headers if
present) into the rootfs using `dpkg-deb --extract`. When multiple kernel `.deb`
versions exist in `build/`, the newest by modification time is selected (`ls -t | head -1`).
Skips the kernel if the same version is already installed.

After each extraction, repairs the merged-usr `/lib → usr/lib` symlink if
`dpkg-deb --extract` replaced it with a real directory (which happens because
the kernel deb contains `./lib/modules/...` entries). Without this repair,
`/sbin/init → /lib/systemd/systemd` becomes a dangling symlink and the board
fails to boot.

### 02_user_setup.sh

Creates the primary user account using direct file manipulation (no `chroot`
required). Writes `/etc/passwd`, `/etc/shadow` (SHA-512 hashed password via
`openssl passwd -6`), and `/etc/group`. Sets the user's password from `USER_PASS`. Sets the root password to a random 256-bit value generated at build time (effectively locks root — use `sudo` via the primary user instead). Adds the user
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
standard Linux naming for USB WiFi with a known MAC address). Generates the
connection UUID via `uuidgen` with a fallback to `/proc/sys/kernel/random/uuid`
(needed when run inside Docker where `uuidgen` is absent).

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

Writes `/boot/extlinux/extlinux.conf` (reference copy, **not** read by
U-Boot) and `/etc/default/u-boot` with `PARTUUID=4c503348-02` (rootfs is
partition 2). Runs last to override anything `u-boot-update` may have
generated. Also removes Armbian-style boot files (`boot.scr`, `boot.cmd`,
`armbianEnv.txt`) if present.

U-Boot reads the authoritative `extlinux/extlinux.conf` from the FAT boot
partition (`build/input/boot.fat`), created by `mkcustomrootfs.sh`.

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

### Building multiple bases (different distros or GUI/no-GUI)

`mkrootfs.sh` is slow (~30–60 min). Use `CODENAME` in `.env` to keep multiple
base images in `build/` simultaneously — each gets a distinct filename and the
downstream scripts (`mkcustomrootfs.sh`, `mksdimg.sh`) pick the right one
automatically.

**Example — headless trixie + desktop bookworm:**

```shell
# Headless trixie base
CODENAME=trixie NOGUI=1 mkrootfs.sh
# → build/rootfs_base-trixie.ext4

# Desktop bookworm base (leave CODENAME unset → plain filename)
NOGUI=0 mkrootfs.sh
# → build/rootfs_base.ext4
```

Set `CODENAME=trixie` (or unset) in `.env`, then run `mkcustomrootfs.sh` and
`mksdimg.sh` as normal — they will use the matching base and append the codename
to the output image name.

## 40-pin GPIO header

All GPIO pins are on `gpiochip1` (`300b000.pinctrl`, main PIO). Line number =
port-index × 32 + pin (PG = port 6, PH = port 7, PI = port 8).

GPIO access requires membership in the `gpio` group (created by `02_user_setup.sh`)
and the udev rule `60-gpio.rules` (sets `GROUP=gpio MODE=0660` on `/dev/gpiochip*`).
Use `gpiodetect` / `gpioget` / `gpioset` from `gpiod`.

| Pin | Signal | Port | Line | GPIO | Alt functions |
|-----|--------|------|------|------|---------------|
|  1  | 3.3V   | —    | —    | —    | 3.3V power |
|  2  | 5V     | —    | —    | —    | 5V power |
|  3  | PG16   | G    | 208  | yes  | MCLKPWM / AC_ADCXPN |
|  4  | 5V     | —    | —    | —    | 5V power |
|  5  | PG15   | G    | 207  | yes  | I2S2_DIN1 |
|  6  | GND    | —    | —    | —    | GND |
|  7  | PH2    | H    | 226  | no   | UART5_RX / **PWM2** (pwm-fan) |
|  8  | PG6    | G    | 198  | no   | **UART1_TX** / JTAG_DI |
|  9  | GND    | —    | —    | —    | GND |
| 10  | PG7    | G    | 199  | no   | **UART1_RX** / JTAG_CK |
| 11  | PG10   | G    | 202  | yes  | I2S2_MCLK / CKFOUT |
| 12  | PG11   | G    | 203  | yes  | I2S2_BCLK |
| 13  | PG8    | G    | 200  | yes  | UART1_CTS / TWI1_SCK |
| 14  | GND    | —    | —    | —    | GND |
| 15  | PG9    | G    | 201  | yes  | UART1_RTS / TWI1_SDA |
| 16  | PG1    | G    | 193  | yes  | SDC1_CLK |
| 17  | 3.3V   | —    | —    | —    | 3.3V power |
| 18  | PH10   | H    | 234  | yes  | IR_RX |
| 19  | PH7    | H    | 231  | no   | UART2_RTS / **SPI1_CS0** / I2S3_LRCK |
| 20  | GND    | —    | —    | —    | GND |
| 21  | PH8    | H    | 232  | no   | UART2_CTS / **SPI1_CLK** / I2S3 |
| 22  | PH4    | H    | 228  | yes  | SPDIF_OUT |
| 23  | PH6    | H    | 230  | no   | UART2_RX / **SPI1_MISO** / I2S3_BCLK |
| 24  | PH5    | H    | 229  | no   | UART2_TX / **SPI1_MOSI** / I2S3_MCLK |
| 25  | GND    | —    | —    | —    | GND |
| 26  | PH9    | H    | 233  | yes  | SPI1_MISO (alt) |
| 27  | PG18   | G    | 210  | no   | **I2C3_SCL** / TWI3_SCK / UART3_CTS |
| 28  | PG17   | G    | 209  | no   | **I2C3_SDA** / TWI3_SDA / UART3_RTS |
| 29  | PG0    | G    | 192  | yes  | SDC1_CMD |
| 30  | GND    | —    | —    | —    | GND |
| 31  | PG3    | G    | 195  | yes  | SDC1_D1 |
| 32  | PG19   | G    | 211  | yes  | **PWM1** |
| 33  | PH3    | H    | 227  | yes  | UART5_TX / **PWM1** / SPDIF_IN |
| 34  | GND    | —    | —    | —    | GND |
| 35  | PG12   | G    | 204  | yes  | I2S2_LRCK |
| 36  | PG5    | G    | 197  | yes  | SDC1_D3 |
| 37  | PI6    | I    | 262  | yes  | UART2_RX / TWI0_SDA |
| 38  | PG13   | G    | 205  | yes  | I2S2_DOUT0 / AC_ADCRP |
| 39  | GND    | —    | —    | —    | GND |
| 40  | PG14   | G    | 206  | yes  | I2S2_DIN0 / AC_ADCXP |

Pins not on header (reserved):

| Port | Line | Use |
|------|------|-----|
| PG2  | 194  | LED0 — heartbeat (kernel gpio-leds, `GPIO_ACTIVE_HIGH`) |
| PG4  | 196  | LED1 — kernel gpio-leds (`GPIO_ACTIVE_LOW`); not exported to header |
| PH0  | 224  | UART0_TX — serial console (`/dev/ttyS0`); also on side debug header (2×2: 5V, TX, GND, RX) |
| PH1  | 225  | UART0_RX — serial console (`/dev/ttyS0`); also on side debug header (2×2: 5V, TX, GND, RX) |

The side debug header also exposes a 5V pin connected to the board's 5V rail. **Do not connect 5V on the debug header if the board is already powered via USB-C** — both supplies would be shorted together.

Interfaces enabled in DTS: `uart1` (PG6/7), `i2c3` (PG18/17), `spi1` (PH5–8), `pwm` (PH2/3 via `pwm-fan`).

## GPU benchmark

Tested with `glmark2-drm` (DRM/KMS backend, no X11 required) on kernel 6.18.19 + Mesa 22.3.6:

```
GL_VENDOR:   Panfrost
GL_RENDERER: Mali-G31 (Panfrost)
GL_VERSION:  OpenGL ES 3.1 Mesa 22.3.6
Resolution:  1920×1080 fullscreen
```

| Scene | FPS |
|-------|-----|
| build (no VBO) | 153 |
| build (VBO) | 153 |
| shading (gouraud) | 103 |
| bump | 271 |
| effect2d | 359 |
| **glmark2 Score** | **206** |

To run the benchmark yourself:

```shell
sudo apt install glmark2-drm
glmark2-drm --size 1280x720
```
