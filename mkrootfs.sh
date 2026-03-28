#!/usr/bin/env bash
# Build rootfs directly into build/rootfs_base.ext4 (no intermediate tar).
# Usage: bash mkrootfs.sh

# load .env
set -a && source .env && set +a

if [ -z "$MMDEBSTRAP" ]; then MMDEBSTRAP=mmdebstrap; fi
if [ -z "$MIRROR" ]; then MIRROR=http://deb.debian.org; fi
if [ -z "$CODENAME" ]; then CODENAME=bookworm; NEOFETCH="neofetch"; fi
if [ -z "$USER_PACKAGE" ]; then USER_PACKAGE=""; fi

BASE_PACKAGE="ca-certificates locales dosfstools binutils file \
	tree sudo bash-completion memtester openssh-server wireless-regdb \
	wpasupplicant systemd-timesyncd usbutils parted systemd-sysv \
	iperf3 stress-ng avahi-daemon tmux screen i2c-tools net-tools \
	ethtool ckermit lrzsz minicom picocom btop $NEOFETCH iotop htop \
	bmon e2fsprogs nvi tcpdump alsa-utils squashfs-tools evtest \
	pssh tcl-expect tcl atftp udpcast u-boot-menu initramfs-tools \
	bluez bluez-hcidump bluez-tools btscanner bluez-alsa-utils \
	device-tree-compiler debian-archive-keyring linux-cpupower \
        network-manager \
	"

if [ -z "$DESKTOP_PACKAGE" ]; then
    DESKTOP_PACKAGE="chromium task-xfce-desktop \
    xfce4-terminal xfce4-screenshooter pulseaudio-module-bluetooth \
    blueman fonts-noto-core fonts-noto-cjk fonts-noto-mono \
    fonts-noto-ui-core tango-icon-theme"
fi

if [ "${NOGUI}" -eq 1 ]; then DESKTOP_PACKAGE=""; fi

mkdir -p build

set -euxo pipefail

BASE_EXT4="./build/rootfs_base.ext4"
MNT="./build/rootfs_mnt"

# Create sparse ext4 image — 6G pre-allocated but uses no disk blocks until written
rm -f "$BASE_EXT4"
truncate -s 6G "$BASE_EXT4"
mkfs.ext4 -L lpi3h-root "$BASE_EXT4"
mkdir -p "$MNT"

# removed options:
# --hook-dir=./hooks \
# --aptopt='Acquire::HTTP::Proxy "http://aptcacheserver:8000";' \

# Pipe mmdebstrap tar output directly into the mounted ext4 (no intermediate tar file)
if [ $(id -u) -ne 0 ]; then
    fuse2fs -o fakeroot "$BASE_EXT4" "$MNT"
    echo "
deb [trusted=yes] ${MIRROR}/debian/ ${CODENAME} main contrib non-free non-free-firmware
deb [trusted=yes] ${MIRROR}/debian/ ${CODENAME}-updates main contrib non-free non-free-firmware
" | $MMDEBSTRAP \
        --aptopt='Acquire::HTTP::Proxy "http://192.168.254.81:8080";' \
        --aptopt='Dir::Etc::Trusted "/usr/share/keyrings/debian-archive-keyring.gpg"' --architectures=arm64 -v -d \
        --aptopt='Dir::Etc::Trusted "/etc/apt/keyrings/debian-archive-keyring.gpg"' \
        --include="${BASE_PACKAGE} ${DESKTOP_PACKAGE} ${USER_PACKAGE}" \
    | fakeroot -- tar --numeric-owner -xpf - -C "$MNT"
    fusermount -u "$MNT"
else
    mount "$BASE_EXT4" "$MNT"
    echo "
deb [trusted=yes] ${MIRROR}/debian/ ${CODENAME} main contrib non-free non-free-firmware
deb [trusted=yes] ${MIRROR}/debian/ ${CODENAME}-updates main contrib non-free non-free-firmware
" | $MMDEBSTRAP \
        --aptopt='Acquire::HTTP::Proxy "http://192.168.254.81:8080";' \
        --aptopt='Dir::Etc::Trusted "/usr/share/keyrings/debian-archive-keyring.gpg"' --architectures=arm64 -v -d \
        --aptopt='Dir::Etc::Trusted "/etc/apt/keyrings/debian-archive-keyring.gpg"' \
        --include="${BASE_PACKAGE} ${DESKTOP_PACKAGE} ${USER_PACKAGE}" \
    | tar --numeric-owner -xpf - -C "$MNT"
    umount "$MNT"
fi

rmdir "$MNT"
e2fsck -fp "$BASE_EXT4"

echo "mkrootfs done. Base image: $BASE_EXT4"
