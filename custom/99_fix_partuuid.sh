#!/usr/bin/env bash
# Write Armbian-style boot files (boot.cmd, boot.scr, armbianEnv.txt) and
# /etc/default/u-boot using the ext4 filesystem UUID as the root device.
#
# Using UUID= (ext4 filesystem UUID) rather than PARTUUID= (MBR disk signature)
# so that tools like DietPi installer that regenerate the MBR signature don't
# break the boot.
#
# Runs last in the customization pipeline to override any extlinux.conf that
# u-boot-update may have generated during kernel deb installation.
#
# Boot files MUST be created here at image-build time, not on a live board.
# Reason: U-Boot's ext4 driver cannot read inodes in block groups > ~3 on
# this filesystem (meta_bg limitation). Files written to a live board land in
# high block groups (inode ~680k+) and are silently unreadable by U-Boot.
#
# Requires: mkimage (u-boot-tools) on the build host / in Docker.
#
# $1 = target rootfs directory

set -euo pipefail

ROOTFS="$1"

KVER=$(ls "$ROOTFS/boot/vmlinuz-"* 2>/dev/null | head -1 | sed "s|.*/vmlinuz-||")
if [ -z "$KVER" ]; then
    echo "ERROR: no kernel found in $ROOTFS/boot"
    exit 1
fi

# Detect the ext4 UUID of the mounted rootfs image
ROOT_UUID=$(findmnt -no UUID "$ROOTFS" 2>/dev/null || \
            blkid -s UUID -o value "$(findmnt -no SOURCE "$ROOTFS")" 2>/dev/null)
if [ -z "$ROOT_UUID" ]; then
    echo "ERROR: could not determine UUID of $ROOTFS"
    exit 1
fi

echo "99_fix_partuuid: kernel=${KVER}  UUID=${ROOT_UUID}"

# --- /etc/default/u-boot (kept for u-boot-update compatibility) ---
mkdir -p "$ROOTFS/etc/default"
cat > "$ROOTFS/etc/default/u-boot" << EOF
## /etc/default/u-boot
U_BOOT_PARAMETERS="console=tty0 console=ttyS0,115200 rootwait earlycon clk_ignore_unused rw"
U_BOOT_ROOT="root=UUID=${ROOT_UUID}"
EOF

# --- /boot/boot.cmd ---
# U-Boot variables (\${devtype} etc.) are escaped so the shell does not expand
# them — only KVER and ROOT_UUID are substituted by the shell here.
mkdir -p "$ROOTFS/boot"
cat > "$ROOTFS/boot/boot.cmd" << EOF
# LonganPi 3H boot script — Armbian-compatible
# Edit /boot/armbianEnv.txt to override defaults

setenv rootdev UUID=${ROOT_UUID}
setenv rootfstype ext4
setenv fdtfile allwinner/sun50i-h618-longanpi-3h.dtb
setenv overlay_prefix sun50i-h616
setenv extraargs

if test -e \${devtype} \${devnum}:\${distro_bootpart} /boot/armbianEnv.txt; then
    load \${devtype} \${devnum}:\${distro_bootpart} \${scriptaddr} /boot/armbianEnv.txt
    env import -t -r \${scriptaddr} \${filesize}
fi

setenv bootargs "root=\${rootdev} rootfstype=\${rootfstype} rootwait console=tty0 console=ttyS0,115200 earlycon clk_ignore_unused rw \${extraargs}"

load \${devtype} \${devnum}:\${distro_bootpart} \${kernel_addr_r} /boot/vmlinuz-${KVER}
load \${devtype} \${devnum}:\${distro_bootpart} \${fdt_addr_r} /usr/lib/linux-image-${KVER}/\${fdtfile}

booti \${kernel_addr_r} - \${fdt_addr_r}
EOF

# --- /boot/boot.scr (compiled from boot.cmd) ---
mkimage -C none -A arm64 -T script -d "$ROOTFS/boot/boot.cmd" "$ROOTFS/boot/boot.scr"

# --- /boot/armbianEnv.txt ---
# extraargs carries the HDMI mode hint. Needed on some monitors in power-save
# at boot; may not be required for all setups.
cat > "$ROOTFS/boot/armbianEnv.txt" << EOF
verbosity=1
bootlogo=false
overlay_prefix=sun50i-h616
fdtfile=allwinner/sun50i-h618-longanpi-3h.dtb
rootdev=UUID=${ROOT_UUID}
rootfstype=ext4
extraargs=video=HDMI-A-1:1280x720@60
EOF

# --- Remove extlinux.conf ---
# U-Boot checks extlinux/extlinux.conf BEFORE boot.scr. Remove it so U-Boot
# falls through to boot.scr. Keep .bak as a manual recovery fallback.
if [ -e "$ROOTFS/boot/extlinux/extlinux.conf" ]; then
    mv "$ROOTFS/boot/extlinux/extlinux.conf" \
       "$ROOTFS/boot/extlinux/extlinux.conf.bak"
    echo "Renamed extlinux.conf → extlinux.conf.bak (recovery fallback)"
fi

echo "Boot files written:"
ls -lh "$ROOTFS/boot/boot.cmd" "$ROOTFS/boot/boot.scr" "$ROOTFS/boot/armbianEnv.txt"
echo "$0 done."
