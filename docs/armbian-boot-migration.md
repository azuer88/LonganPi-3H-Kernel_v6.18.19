# Armbian U-Boot Convention Migration — LonganPi 3H

## Context

The default build system uses `extlinux/extlinux.conf` for U-Boot boot configuration.
DietPi installer (and Armbian-based tools) expect `boot.scr` + `armbianEnv.txt` instead.
This documents the manual steps applied to `lpi3h-f1a0` to switch conventions,
intended as a reference for updating the build scripts to produce images using
Armbian-style boot by default.

---

## What was done on the live board

### 1. Install `u-boot-tools`

```sh
sudo apt-get install -y u-boot-tools
```

Needed for `mkimage` to compile `boot.cmd` → `boot.scr`.

---

### 2. Write `/boot/boot.cmd`

```sh
sudo tee /boot/boot.cmd << 'EOF'
# LonganPi 3H boot script — Armbian-compatible
# Edit /boot/armbianEnv.txt to override defaults

setenv rootdev "PARTUUID=4c503348-01"
setenv rootfstype "ext4"
setenv fdtfile "allwinner/sun50i-h618-longanpi-3h.dtb"
setenv overlay_prefix "sun50i-h616"
setenv extraargs ""

if test -e ${devtype} ${devnum}:${distro_bootpart} /boot/armbianEnv.txt; then
    load ${devtype} ${devnum}:${distro_bootpart} ${scriptaddr} /boot/armbianEnv.txt
    env import -t -r ${scriptaddr} ${filesize}
fi

setenv bootargs "root=${rootdev} rootfstype=${rootfstype} rootwait console=tty0 console=ttyS0,115200 earlycon clk_ignore_unused rw ${extraargs}"

load ${devtype} ${devnum}:${distro_bootpart} ${kernel_addr_r} /boot/vmlinuz-6.18.19
load ${devtype} ${devnum}:${distro_bootpart} ${fdt_addr_r} /usr/lib/linux-image-6.18.19/${fdtfile}

booti ${kernel_addr_r} - ${fdt_addr_r}
EOF
```

Notes:
- Kernel filename is hardcoded to `vmlinuz-6.18.19` — must be made dynamic when
  porting to the build scripts (detect from `/boot/vmlinuz-*` like `99_fix_partuuid.sh` does).
- DTB path is `/usr/lib/linux-image-6.18.19/${fdtfile}` — this is where our kernel
  deb installs DTBs. Armbian puts DTBs at `/boot/dtb/${fdtfile}` — if DietPi installer
  expects that path, a symlink or copy will be needed.
- U-Boot addresses confirmed from binary:
  - `kernel_addr_r=0x40080000`
  - `fdt_addr_r=0x4FA00000`
  - `ramdisk_addr_r=0x4FF00000`
  - `scriptaddr=0x4FC00000`

---

### 3. Compile `boot.cmd` → `boot.scr`

```sh
sudo mkimage -C none -A arm64 -T script -d /boot/boot.cmd /boot/boot.scr
```

Output:
```
Image Type: AArch64 Linux Script (uncompressed)
Data Size:  395 Bytes
```

---

### 4. Write `/boot/armbianEnv.txt`

```sh
sudo tee /boot/armbianEnv.txt << 'EOF'
verbosity=1
bootlogo=false
overlay_prefix=sun50i-h616
fdtfile=allwinner/sun50i-h618-longanpi-3h.dtb
rootdev=PARTUUID=4c503348-01
rootfstype=ext4
extraargs=video=HDMI-A-1:1280x720@60
EOF
```

Notes:
- `extraargs` carries the HDMI mode hint — needed on some monitors that are in
  power-save at boot. May not be required for all setups.
- `overlay_prefix=sun50i-h616` — used by DietPi/Armbian overlay system. H618 uses
  the H616 prefix.
- `rootdev` must match the MBR disk signature set by `mksdimg.sh` (`0x4c503348`).

---

### 5. Disable `extlinux.conf`

```sh
sudo mv /boot/extlinux/extlinux.conf /boot/extlinux/extlinux.conf.bak
```

**Why:** Our U-Boot checks `extlinux/extlinux.conf` BEFORE `boot.scr` (confirmed from
binary: `scan_dev_for_extlinux` runs before `scan_dev_for_scripts`). Renaming it
forces U-Boot to fall through to `boot.scr`.

The `.bak` file is kept as a fallback — restore it if boot.scr fails.

---

## Boot file layout after migration

```
/boot/
  boot.cmd           ← source script (human-readable)
  boot.scr           ← compiled script (U-Boot loads this)
  armbianEnv.txt     ← variables read by boot.cmd
  vmlinuz-6.18.19
  extlinux/
    extlinux.conf.bak  ← disabled (was extlinux.conf)
/usr/lib/linux-image-6.18.19/
  allwinner/sun50i-h618-longanpi-3h.dtb
```

---

## How U-Boot finds boot.scr

U-Boot distro boot scans in this order per device/partition:
1. `extlinux/extlinux.conf` — now absent → skip
2. `boot.scr` / `boot.scr.uimg` — found → execute

---

## What needs to change in the build scripts

### `99_fix_partuuid.sh`
Replace the `extlinux.conf` and `/etc/default/u-boot` writes with:

1. Write `/boot/boot.cmd` (template above, with `KVER` variable substitution)
2. Run `mkimage -C none -A arm64 -T script -d /boot/boot.cmd /boot/boot.scr`
   - Requires `u-boot-tools` in the rootfs — already in `BASE_PACKAGE`
     (`u-boot-menu` pulls it in) — verify this, or add `u-boot-tools` explicitly.
3. Write `/boot/armbianEnv.txt` with the variables above
4. Do NOT write `extlinux/extlinux.conf`
5. Still write `/etc/default/u-boot` for `u-boot-update` compatibility

### `custom/01_install_debs.sh`
After kernel deb install, `u-boot-update` regenerates `extlinux.conf`.
With the new convention, we want it to regenerate `boot.scr` instead — or just
not run `u-boot-update` at all (since `99_fix_partuuid.sh` writes boot files last anyway).

### DTB path consideration
Our kernel installs DTBs to `/usr/lib/linux-image-KVER/allwinner/`.
Armbian tools expect `/boot/dtb/allwinner/`. Options:
- Symlink: `ln -s /usr/lib/linux-image-KVER /boot/dtb` in `99_fix_partuuid.sh`
- Or keep loading from `/usr/lib/linux-image-KVER/` in `boot.cmd` (works, non-standard)

### `mkrootfs.sh` / `BASE_PACKAGE`
Verify `u-boot-tools` is present (needed for `mkimage` at image-build time in
`99_fix_partuuid.sh`). Currently `u-boot-menu` is in BASE_PACKAGE which may
pull it in as a dependency — confirm or add `u-boot-tools` explicitly.
