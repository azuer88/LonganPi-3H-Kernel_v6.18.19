#!/usr/bin/env bash
# Create user, set passwords, configure groups, enable avahi workstation
# Uses direct file manipulation (compatible with fakeroot — no chroot needed)
# $1 = target rootfs directory

set -a && source .env && set +a

if [ -z "${USER_NAME:-}" ] || [ -z "${USER_PASS:-}" ]; then
    echo "USER_NAME or USER_PASS not defined, skipping."
    exit 0
fi

ROOTFS="$1"
U_UID=1000
U_GID=1000

# --- Create home directory from skel ---
if [ ! -d "$ROOTFS/home/$USER_NAME" ]; then
    mkdir -p "$ROOTFS/home/$USER_NAME"
    cp -a "$ROOTFS/etc/skel/." "$ROOTFS/home/$USER_NAME/"
fi
chown -R ${U_UID}:${U_GID} "$ROOTFS/home/$USER_NAME"

# --- /etc/passwd entry ---
if ! grep -q "^${USER_NAME}:" "$ROOTFS/etc/passwd"; then
    echo "${USER_NAME}:x:${U_UID}:${U_GID}:,,,:/home/${USER_NAME}:/bin/bash" \
        >> "$ROOTFS/etc/passwd"
    echo "Added $USER_NAME to /etc/passwd"
fi

# --- /etc/shadow entry (SHA-512 hashed password) ---
if ! grep -q "^${USER_NAME}:" "$ROOTFS/etc/shadow"; then
    HASH=$(openssl passwd -6 "$USER_PASS")
    echo "${USER_NAME}:${HASH}:19900:0:99999:7:::" >> "$ROOTFS/etc/shadow"
    echo "Added $USER_NAME to /etc/shadow"
fi

# --- Root password (random, generated at build time — effectively locks root) ---
ROOT_HASH=$(openssl rand -base64 32 | openssl passwd -6 -stdin)
sed -i "s|^root:[^:]*:|root:${ROOT_HASH}:|" "$ROOTFS/etc/shadow"

# --- /etc/group: create primary group and add to supplementary groups ---
if ! grep -q "^${USER_NAME}:" "$ROOTFS/etc/group"; then
    echo "${USER_NAME}:x:${U_GID}:" >> "$ROOTFS/etc/group"
fi

# Ensure gpio group exists (needed for udev rule on /dev/gpiochip*)
if ! grep -q "^gpio:" "$ROOTFS/etc/group"; then
    # Pick next available GID above 999
    NEXT_GID=$(awk -F: '$3 >= 1000 { print $3 }' "$ROOTFS/etc/group" | sort -n | tail -1)
    NEXT_GID=$(( ${NEXT_GID:-1000} + 1 ))
    echo "gpio:x:${NEXT_GID}:" >> "$ROOTFS/etc/group"
fi

for GRP in dialout cdrom audio video render plugdev users netdev input sudo gpio; do
    if grep -q "^${GRP}:" "$ROOTFS/etc/group"; then
        # append user to group if not already present
        if ! grep -q "^${GRP}:.*\b${USER_NAME}\b" "$ROOTFS/etc/group"; then
            sed -i "/^${GRP}:/ s/$/,${USER_NAME}/" "$ROOTFS/etc/group"
            # fix leading comma if group member list was empty
            sed -i "/^${GRP}:/ s/:,/:/" "$ROOTFS/etc/group"
        fi
    fi
done

# --- Avahi workstation ---
AVAHI_CONF="$ROOTFS/etc/avahi/avahi-daemon.conf"
if [ -f "$AVAHI_CONF" ]; then
    sed -i "s/workstation=no/workstation=yes/" "$AVAHI_CONF"
    echo "Enabled avahi workstation"
fi

echo "$0 done."
