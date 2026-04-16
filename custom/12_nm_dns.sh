#!/usr/bin/env bash
# Configure NetworkManager to hand DNS off to systemd-resolved (if installed)
# $1 = target rootfs directory

ROOTFS="$1"

# Only apply if systemd-resolved is present in the rootfs
if [ ! -f "$ROOTFS/lib/systemd/systemd-resolved" ] && [ ! -f "$ROOTFS/usr/lib/systemd/systemd-resolved" ]; then
    echo "systemd-resolved not found in rootfs, skipping."
    exit 0
fi

mkdir -p "$ROOTFS/etc/NetworkManager/conf.d"
cat > "$ROOTFS/etc/NetworkManager/conf.d/99-systemd-resolved.conf" << EOF
[main]
dns=systemd-resolved
EOF

echo "$0 done."
