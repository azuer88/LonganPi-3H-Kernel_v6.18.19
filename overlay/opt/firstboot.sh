#!/bin/bash

set -x

PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin
export PATH

# resize root filesystem
echo "yes
100%
" | parted ---pretend-input-tty /dev/mmcblk0 "resizepart 1 100%"
echo "yes
100%
" | parted ---pretend-input-tty /dev/mmcblk1 "resizepart 1 100%"

resize2fs /dev/mmcblk0p1
resize2fs /dev/mmcblk1p1

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
NEW_HOSTHAME=$(</etc/hostname)
# echo "127.0.0.1	$NEW_HOSTNAME" >> /etc/hosts
hostname "$NEW_HOSTNAME"
nmcli general hostname "$NEW_HOSTNAME"
systemctl enable avahi-daemon
systemctl restart avahi-daemon &

# regenerate openssh host keys
dpkg-reconfigure openssh-server

# enable rc-local service
systemctl enable rc-local

# change the timezone
# timedatectl set-timezone Asia/Manila

# get time from network
systemctl enable systemd-timesyncd
systemctl restart systemd-timesyncd &
