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

# --- Disable systemd-networkd-wait-online (we use NetworkManager-wait-online instead) ---
mkdir -p "$ROOTFS/etc/systemd/system"
ln -sf /dev/null "$ROOTFS/etc/systemd/system/systemd-networkd-wait-online.service"

# --- file capabilities: skipped under fakeroot (xattrs require real root) ---
SETCAP=$(command -v setcap || echo /sbin/setcap)
if [ "$(id -u)" -eq 0 ] && [ -x "$SETCAP" ]; then
    # ping: cap_net_raw+ep (iputils-ping postinst skipped when using dpkg-deb --extract)
    [ -x "$ROOTFS/usr/bin/ping" ] && "$SETCAP" cap_net_raw=ep "$ROOTFS/usr/bin/ping"
    # ip: caps for ip vrf exec by non-root (iproute2 postinst debconf defaults to false in non-interactive builds)
    [ -x "$ROOTFS/bin/ip" ] && "$SETCAP" cap_dac_override,cap_sys_admin,cap_net_admin=ep "$ROOTFS/bin/ip"
else
    echo "WARNING: skipping setcap (not root or setcap not found) — ping/ip vrf exec will need caps set manually"
fi

echo "$0 done."
