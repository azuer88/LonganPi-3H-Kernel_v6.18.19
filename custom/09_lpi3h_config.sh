#!/usr/bin/env bash
# Apply LPI3H-specific device configuration fixes
# $1 = target rootfs directory

ROOTFS="$1"

# Fixed PARTUUID matching disk-signature in mksdimg.sh (4c503348 → PARTUUID 4c503348-01)
ROOT_PARTUUID="4c503348-01"

# --- /etc/default/u-boot ---
mkdir -p "$ROOTFS/etc/default"
cat > "$ROOTFS/etc/default/u-boot" << UBOOT
## /etc/default/u-boot - configuration file for u-boot-update(8)

U_BOOT_PARAMETERS="console=tty0 console=ttyS0,115200 rootwait earlycon clk_ignore_unused rw video=HDMI-A-1:1280x720@60"
U_BOOT_ROOT="root=PARTUUID=${ROOT_PARTUUID}"
UBOOT

# --- /boot/extlinux/extlinux.conf ---
# Detect installed kernel version
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
        # include initrd only if it exists
        [ -e "$ROOTFS/boot/initrd.img-${KVER}" ] && echo "	initrd /boot/initrd.img-${KVER}"
        echo "	fdtdir /usr/lib/linux-image-${KVER}/"
        echo "	append root=PARTUUID=${ROOT_PARTUUID} console=tty0 console=ttyS0,115200 rootwait earlycon clk_ignore_unused rw video=HDMI-A-1:1280x720@60"
    } > "$ROOTFS/boot/extlinux/extlinux.conf"
    echo "Created extlinux.conf for kernel ${KVER}"
    cat "$ROOTFS/boot/extlinux/extlinux.conf"
fi

# --- /etc/udev/rules.d/99-no-p2p.rules ---
cat > "$ROOTFS/etc/udev/rules.d/99-no-p2p.rules" << UDEV
# Remove P2P management interface created by wpa_supplicant/NetworkManager
ACTION=="add", SUBSYSTEM=="net", NAME=="p2p-dev-*", RUN+="/sbin/ip link delete \$name"
UDEV

# --- wpa_supplicant: disable P2P globally ---
cat > "$ROOTFS/etc/wpa_supplicant/wpa_supplicant.conf" << WPA
ctrl_interface=DIR=/run/wpa_supplicant GROUP=netdev
p2p_disabled=1
WPA

mkdir -p "$ROOTFS/etc/systemd/system/wpa_supplicant.service.d"
cat > "$ROOTFS/etc/systemd/system/wpa_supplicant.service.d/no-p2p.conf" << SYSD
[Service]
ExecStart=
ExecStart=/sbin/wpa_supplicant -u -s -c /etc/wpa_supplicant/wpa_supplicant.conf -O "DIR=/run/wpa_supplicant GROUP=netdev"
SYSD

echo "$0 done."
