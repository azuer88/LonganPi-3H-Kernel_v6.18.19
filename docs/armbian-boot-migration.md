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

**Critical: `boot.cmd` content was silently corrupted on the live board.**
The heredoc `sudo tee` approach caused `${devtype}`, `${devnum}`, `${distro_bootpart}`
to be expanded (to empty strings) by the shell before reaching tee. The resulting
`boot.cmd` had blank variable references and a truncated `setenv bootargs` line.
Use single-quoted heredoc (`<< 'EOF'`) to prevent expansion, or write the file from
the host onto a mounted filesystem.

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

---

## Boot failure post-migration — root cause and fix

After completing the migration on `lpi3h-f1a0` and rebooting, the board failed
to boot. Diagnosis via U-Boot serial console revealed two independent problems.

### Problem 1: U-Boot ext4 driver cannot read high-numbered inodes

U-Boot reported:
```
Found U-Boot script /boot/boot.scr
Failed to load '/boot/boot.scr'
Wrong image format for "source" command
```

U-Boot could list `/boot/` and see `boot.scr` in the directory, but every
`load` attempt failed. Files created during the original rootfs build
(vmlinuz, System.map, config, extlinux.conf) loaded fine. All files created
on the live board or copied from a host onto the mounted SD card failed.

**Root cause:** The filesystem has the `meta_bg` ext4 feature enabled. U-Boot's
ext4 driver does not correctly locate inode tables for block groups beyond
approximately group 3. Files created at image-build time land in groups 0–3
(inodes ~1–32767). Files created later on a live 30 GB filesystem land in
group 83 (inodes ~680000+). U-Boot can traverse directory entries for all
groups but silently fails to read the inode data for groups it cannot reach,
showing garbage file sizes in `ls` output.

Inode numbers observed:
- `vmlinuz-6.18.19`: inode 5225 (group 0) — loadable
- `extlinux.conf.bak`: inode 29943 (group 3) — loadable
- `boot.scr` (created on live board): inode 680450 (group 83) — **not loadable**
- `extlinux.conf` (copied from host): inode ~680xxx (group 83) — **not loadable**

**Fix applied to get board booting:**
`extlinux.conf` was re-created as a hard link to `extlinux.conf.bak`, reusing
inode 29943 (group 3):
```sh
sudo rm /boot/extlinux/extlinux.conf
sudo ln /boot/extlinux/extlinux.conf.bak /boot/extlinux/extlinux.conf
```
(Done from the host with the SD card mounted at `/media/lou/lpi3h-root/`.)

**Implication for build scripts:**
`boot.scr` and `armbianEnv.txt` **must be created at image-build time**
(inside `99_fix_partuuid.sh` during `mkcustomrootfs.sh`), never on a live
running board and never by copying onto a mounted card. Created during the
build, they receive early inode numbers that U-Boot can reach.

Do not attempt to create these files via SSH on a running board. Any files
written to the live filesystem will land in high block groups and be invisible
to U-Boot.

### Problem 2: boot.cmd variables silently expanded by the shell

The original `sudo tee /boot/boot.cmd << EOF` heredoc (without single quotes
around EOF) caused the shell to expand `${devtype}`, `${devnum}`,
`${distro_bootpart}`, etc. to empty strings before tee received them. The
file on disk contained blank variable references and a truncated
`setenv bootargs` line. When boot.scr was compiled from this corrupted
boot.cmd, it produced a script that would always set empty bootargs and
attempt to load the kernel from device `""` — it could never succeed.

Fix: use `<< 'EOF'` (single-quoted) to suppress shell expansion, or write
the file directly from the build host onto the mounted filesystem.

The correct boot.cmd in `docs/armbian-boot-migration.md` uses `<< 'EOF'`
and is the reference for what `99_fix_partuuid.sh` should write.

### Problem 3: MBR disk signature mismatch

After fixing extlinux.conf (via hard link), the kernel started but hung at:
```
Waiting for root device PARTUUID=4c503348-01...
```
The SD card appeared as `mmcblk1p1` but the kernel never mounted root.

**Root cause:** The MBR disk signature on this card was `0xde54d316` (PARTUUID
`de54d316-01`), not `0x4c503348`. The card had not been originally flashed with
`mksdimg.sh`, which is the only step that writes the fixed signature. The
extlinux.conf (written by `99_fix_partuuid.sh`) correctly says `4c503348-01`,
but nothing ever set the MBR to match.

Verified with:
```sh
sudo dd if=/dev/sdd bs=1 skip=440 count=4 2>/dev/null | xxd
# showed: 16 d3 54 de  (= 0xde54d316 LE)
```

**Fix:** write the correct signature directly to the MBR:
```sh
printf '\x48\x33\x50\x4c' | sudo dd bs=1 seek=440 of=/dev/sdd conv=notrunc
# verify: should show 48 33 50 4c  (= 0x4c503348 LE = PARTUUID 4c503348-01)
```

**Note for live boards not flashed via mksdimg.sh:** any board set up by other
means (manual dd, Raspberry Pi Imager with a different image, etc.) will have a
random MBR signature. Either write the fixed signature as above, or change the
`root=` in extlinux.conf to match the actual PARTUUID (`blkid` or U-Boot
`mmc part` to read it).

### How the board was manually booted during diagnosis

With the card mounted on the host, vmlinuz was confirmed loadable. The board
was booted by interrupting autoboot, then from the U-Boot prompt:

```
load mmc 0:1 0x40080000 /boot/vmlinuz-6.18.19
load mmc 0:1 0x4FA00000 /usr/lib/linux-image-6.18.19/allwinner/sun50i-h618-longanpi-3h.dtb
setenv bootargs "root=PARTUUID=4c503348-01 console=tty0 console=ttyS0,115200 rootwait earlycon clk_ignore_unused rw video=HDMI-A-1:1280x720@60"
booti 0x40080000 - 0x4FA00000
```

This confirmed the kernel, DTB, and PARTUUID were all correct — the only
issue was U-Boot's inability to load the boot script files.
