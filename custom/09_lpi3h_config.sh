#!/usr/bin/env bash
# Apply LPI3H-specific device configuration fixes
# $1 = target rootfs directory

ROOTFS="$1"

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
