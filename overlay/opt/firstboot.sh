#!/bin/bash

set -x

PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin
export PATH

# resize root filesystem
# Find the disk containing the root partition (avoids hardcoding mmcblkN)
ROOT_PART=$(findmnt / -o SOURCE -n)           # e.g. /dev/mmcblk1p2
ROOT_DISK=${ROOT_PART%p[0-9]*}                # e.g. /dev/mmcblk1
ROOT_PARTNUM=${ROOT_PART##*p}                 # e.g. 2

# Save disk signature before parted (parted randomises it on some versions)
SAVED_SIG=$(dd if="$ROOT_DISK" bs=1 skip=440 count=4 2>/dev/null | od -A n -t x1 | tr -d ' \n')

echo "yes
100%
" | parted ---pretend-input-tty "$ROOT_DISK" "resizepart $ROOT_PARTNUM 100%"

# Restore original disk signature so PARTUUID stays consistent
printf "\x${SAVED_SIG:0:2}\x${SAVED_SIG:2:2}\x${SAVED_SIG:4:2}\x${SAVED_SIG:6:2}" \
    | dd of="$ROOT_DISK" bs=1 seek=440 conv=notrunc 2>/dev/null

resize2fs "$ROOT_PART"

# dont use buggy systemd-resolved
echo "nameserver 8.8.8.8" >> /etc/resolv.conf

# generate locale data
# echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen
cat << EOF >> /etc/locale.gen
en_PH ISO-8859-1
en_PH.UTF-8 UTF-8
en_US.UTF-8 UTF-8
fil_PH UTF-8
tl_PH ISO-8859-1
tl_PH.UTF-8 UTF-8

EOF

locale-gen

# change hostname
# NEW_HOSTNAME="lpi3h-$(cat /sys/class/net/end0/address | tr -d ':\n' | tail -c 4)"
# echo "NEW HOSTNAME: $NEW_HOSTNAME"
# echo "$NEW_HOSTNAME" > /etc/hostname
NEW_HOSTNAME=$(</etc/hostname)
# echo "127.0.0.1	$NEW_HOSTNAME" >> /etc/hosts
hostname "$NEW_HOSTNAME"
nmcli general hostname "$NEW_HOSTNAME"
systemctl enable avahi-daemon
systemctl restart avahi-daemon &

# SSH host keys are pre-generated at image build time (03_ssh_host_keys.sh);
# do not regenerate them here or the stable fingerprint will be lost.

# enable rc-local service
systemctl enable rc-local

# change the timezone
# timedatectl set-timezone Asia/Manila

# get time from network
systemctl enable systemd-timesyncd
systemctl restart systemd-timesyncd &
