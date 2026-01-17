#!/usr/bin/env bash

# load .env
set -a && source .env && set +a


if [ -z "$MMDEBSTRAP" ]
then
    MMDEBSTRAP=mmdebstrap
fi

if [ -z "$MIRROR" ]
then
    MIRROR=http://deb.debian.org
    # MIRROR="http://ftp.debian.org"
    # MIRROR="http://cdn-fastly.deb.debian.org"
fi

if [ -z "$CODENAME" ]
then
    CODENAME=bookworm
    NEOFETCH="neofetch" # neofetch or fastfetch
fi

if [ -z "$USER_PACKAGE" ]
then
    USER_PACKAGE=""
fi
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
	build-essential libevent-dev libjpeg-dev libbsd-dev git pkg-config \
	curl \
	gpiod lm-sensors
	"


if [ -z "$DESKTOP_PACKAGE" ]
then
    DESKTOP_PACKAGE="chromium task-xfce-desktop \
    xfce4-terminal xfce4-screenshooter pulseaudio-module-bluetooth \
    blueman fonts-noto-core fonts-noto-cjk fonts-noto-mono \
    fonts-noto-ui-core tango-icon-theme"
fi

# NOGUI=1 load from .env 
if [ "${NOGUI}" -eq 1 ]
then
    DESKTOP_PACKAGE=""
fi

mkdir build

set -eux


genrootfs() {
    if [ -n "${APT_PROXY:-}" ]; then
        APTOPT=""
    else
        APTOPT="--aptopt='Acquire::HTTP::Proxy \"$APT_PROXY\";'"
    fi
    echo "
deb [trusted=yes] ${MIRROR}/debian/ ${CODENAME} main contrib non-free non-free-firmware
deb [trusted=yes] ${MIRROR}/debian/ ${CODENAME}-updates main contrib non-free non-free-firmware
" | $MMDEBSTRAP \
        --aptopt='Acquire::HTTP::Proxy "http://aptcacheserver:8000";' \
        --aptopt='Dir::Etc::Trusted "/usr/share/keyrings/debian-archive-keyring.gpg"' --architectures=arm64 -v -d \
	--aptopt='Dir::Etc::Trusted "/etc/apt/keyrings/debian-archive-keyring.gpg"' \
        --hook-dir=./hooks \
		--include="${BASE_PACKAGE} ${DESKTOP_PACKAGE} ${USER_PACKAGE}" > ./build/rootfs.tar
}

genrootfs
