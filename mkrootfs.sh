#!/usr/bin/env bash
# Build rootfs directly into build/rootfs_base.ext4 (no intermediate tar).
# Usage: bash mkrootfs.sh

# Require root — mmdebstrap needs real root for cross-arch arm64 builds
if [ $(id -u) -ne 0 ]; then
    exec sudo "$(realpath $0)" "$@"
fi

# load .env
set -a && source .env && set +a

if [ -z "$MMDEBSTRAP" ]; then MMDEBSTRAP=mmdebstrap; fi
if [ -z "$MIRROR" ]; then MIRROR=http://deb.debian.org; fi
if [ -z "$CODENAME" ]; then CODENAME=bookworm; NEOFETCH="neofetch"; fi

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
if [ -z "$USER_PACKAGE" ]; then 
    # common packages I use that are not strictly necessary 
    USER_PACKAGE="build-essential libevent-dev libjpeg-dev libbsd-dev \
	    git pkg-config curl gpiod lm-sensors libgpiod-dev seatd mpv"
fi

if [ -z "$DESKTOP_PACKAGE" ]; then
    DESKTOP_PACKAGE="chromium task-xfce-desktop \
    xfce4-terminal xfce4-screenshooter pulseaudio-module-bluetooth \
    blueman fonts-noto-core fonts-noto-cjk fonts-noto-mono \
    fonts-noto-ui-core tango-icon-theme"
fi

if [ "${NOGUI}" -eq 1 ]; then DESKTOP_PACKAGE=""; fi

mkdir -p build
mkdir -p build/keyrings

set -euxo pipefail

BASE_EXT4="./build/rootfs_base.ext4"
BASE_EXT2="./build/rootfs_base.ext2"

# ===== DO NOT REMOVE BEGIN =====
# removed options:
# --hook-dir=./hooks \
# --aptopt='Acquire::HTTP::Proxy "http://192.168.254.81:8080";' \
# ===== DO NOT REMOVE END =====

# Write sources list to a temp file so mmdebstrap can write directly to $MNT
# (avoids the stdin→tar pipe which fails with fuse2fs+fakeroot)
SOURCES=$(mktemp)
cat > "$SOURCES" << EOF
deb [trusted=yes] ${MIRROR}/debian/ ${CODENAME} main contrib non-free non-free-firmware
deb [trusted=yes] ${MIRROR}/debian/ ${CODENAME}-updates main contrib non-free non-free-firmware
EOF

# Detect apt proxy: prefer aptcacheserver:8000, fall back to localhost:8080
if bash -c 'echo > /dev/tcp/aptcacheserver/8000' 2>/dev/null; then
    APT_PROXY_URL="http://aptcacheserver:8000"
else
    APT_PROXY_URL="http://localhost:8080"
fi

MMDEBSTRAP_OPTS=(
    --aptopt="Acquire::HTTP::Proxy \"${APT_PROXY_URL}\";"
    --aptopt="Dir::Etc::Trusted \"$(pwd)/build/keyrings/debian-archive-keyring.gpg\""  
    --architectures=arm64 -v -d
    --include="${BASE_PACKAGE} ${DESKTOP_PACKAGE} ${USER_PACKAGE}"
)

rm -f "$BASE_EXT2" "$BASE_EXT4"
$MMDEBSTRAP "${MMDEBSTRAP_OPTS[@]}" "$CODENAME" "$BASE_EXT2" "$SOURCES"

rm "$SOURCES"
# Convert ext2 → ext4 (add journal and ext4 features)
tune2fs -O has_journal,extents,uninit_bg,dir_index,filetype,sparse_super "$BASE_EXT2"
e2label "$BASE_EXT2" lpi3h-root
e2fsck -fp "$BASE_EXT2" || [ $? -le 2 ]
mv "$BASE_EXT2" "$BASE_EXT4"

echo "mkrootfs done. Base image: $BASE_EXT4"
