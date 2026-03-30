#!/usr/bin/env bash
# Write /boot/extlinux/extlinux.conf with the correct PARTUUID and kernel
# paths. Runs last in the customization pipeline to override anything
# u-boot-update may have generated during kernel deb installation.
#
# Boot files MUST be created here at image-build time, not on a live board.
# Reason: U-Boot's ext4 driver cannot read inodes in block groups > ~3 on
# this filesystem (meta_bg limitation). Files written to a live board land in
# high block groups (inode ~680k+) and are silently unreadable by U-Boot.
#
# Root device is specified as PARTUUID= (MBR disk signature), not UUID=
# (ext4 filesystem UUID). PARTUUID= is resolved by the kernel's partition
# layer before any filesystem code runs. UUID= requires scanning ext4
# superblocks which races with the mmc driver initialising, causing
# "Disabling rootwait; root= is invalid" kernel panics on this board.
#
# The MBR disk signature is hardcoded to 0x4c503348 in mksdimg.sh, making
# the root partition always PARTUUID=4c503348-01.
#
# Note: DietPi installer overwrites the MBR disk signature. After running
# DietPi installer, restore the signature with:
#   printf '\x48\x33\x50\x4c' | sudo dd bs=1 seek=440 of=/dev/mmcblk0 conv=notrunc
#
# $1 = target rootfs directory

set -euo pipefail

ROOTFS="$1"
ROOT_PARTUUID="4c503348-01"

KVER=$(ls "$ROOTFS/boot/vmlinuz-"* 2>/dev/null | head -1 | sed "s|.*/vmlinuz-||")
if [ -z "$KVER" ]; then
    echo "ERROR: no kernel found in $ROOTFS/boot"
    exit 1
fi

echo "99_fix_partuuid: kernel=${KVER}  PARTUUID=${ROOT_PARTUUID}"

# --- /etc/default/u-boot (for u-boot-update compatibility) ---
mkdir -p "$ROOTFS/etc/default"
cat > "$ROOTFS/etc/default/u-boot" << EOF
## /etc/default/u-boot
U_BOOT_PARAMETERS="console=tty0 console=ttyS0,115200 rootwait earlycon clk_ignore_unused rw video=HDMI-A-1:1280x720@60"
U_BOOT_ROOT="root=PARTUUID=${ROOT_PARTUUID}"
EOF

# --- /boot/extlinux/extlinux.conf ---
mkdir -p "$ROOTFS/boot/extlinux"
cat > "$ROOTFS/boot/extlinux/extlinux.conf" << EOF
timeout 30
default l0

label l0
    kernel /boot/vmlinuz-${KVER}
    fdt /usr/lib/linux-image-${KVER}/allwinner/sun50i-h618-longanpi-3h.dtb
    append root=PARTUUID=${ROOT_PARTUUID} rootfstype=ext4 rootwait console=tty0 console=ttyS0,115200 earlycon clk_ignore_unused rw video=HDMI-A-1:1280x720@60
EOF

# --- Remove Armbian-style boot files if present ---
for f in boot.cmd boot.scr armbianEnv.txt; do
    [ -e "$ROOTFS/boot/$f" ] && rm -f "$ROOTFS/boot/$f" && echo "Removed /boot/$f"
done

echo "Boot files written:"
cat "$ROOTFS/boot/extlinux/extlinux.conf"
echo "$0 done."
