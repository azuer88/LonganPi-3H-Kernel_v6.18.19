#!/usr/bin/env bash
# Write /etc/default/u-boot and /boot/extlinux/extlinux.conf with the correct
# PARTUUID, overriding whatever u-boot-update may have generated.
#
# The MBR disk signature is hardcoded to 0x4c503348 in mksdimg.sh, so the
# root partition is always PARTUUID=4c503348-01.
# $1 = target rootfs directory

ROOTFS="$1"
ROOT_PARTUUID="4c503348-01"

# --- /etc/default/u-boot ---
mkdir -p "$ROOTFS/etc/default"
cat > "$ROOTFS/etc/default/u-boot" << UBOOT
## /etc/default/u-boot - configuration file for u-boot-update(8)

U_BOOT_PARAMETERS="console=tty0 console=ttyS0,115200 rootwait earlycon clk_ignore_unused rw video=HDMI-A-1:1280x720@60"
U_BOOT_ROOT="root=PARTUUID=${ROOT_PARTUUID}"
UBOOT

# --- /boot/extlinux/extlinux.conf ---
KVER=$(ls "$ROOTFS/boot/vmlinuz-"* 2>/dev/null | head -1 | sed "s|.*/vmlinuz-||")

if [ -z "$KVER" ]; then
    echo "WARNING: no kernel found in $ROOTFS/boot, skipping extlinux.conf"
else
    mkdir -p "$ROOTFS/boot/extlinux"
    {
        echo "## /boot/extlinux/extlinux.conf"
        echo ""
        echo "default l0"
        echo "menu title U-Boot menu"
        echo "prompt 0"
        echo "timeout 50"
        echo ""
        echo "label l0"
        echo "	menu label Debian GNU/Linux bookworm ${KVER}"
        echo "	linux /boot/vmlinuz-${KVER}"
        [ -e "$ROOTFS/boot/initrd.img-${KVER}" ] && echo "	initrd /boot/initrd.img-${KVER}"
        echo "	fdtdir /usr/lib/linux-image-${KVER}/"
        echo "	append root=PARTUUID=${ROOT_PARTUUID} console=tty0 console=ttyS0,115200 rootwait earlycon clk_ignore_unused rw video=HDMI-A-1:1280x720@60"
    } > "$ROOTFS/boot/extlinux/extlinux.conf"
    echo "Created extlinux.conf for kernel ${KVER}"
    cat "$ROOTFS/boot/extlinux/extlinux.conf"
fi

echo "$0 done."
