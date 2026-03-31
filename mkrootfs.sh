#!/usr/bin/env bash
# Build rootfs directly into build/rootfs_base.ext4 (no intermediate tar).
# Usage: bash mkrootfs.sh

# Require root — mmdebstrap needs real root for cross-arch arm64 builds
if [ $(id -u) -ne 0 ]; then
    exec sudo "$(realpath $0)" "$@"
fi

pushd "$(dirname "$(realpath "$0")")" > /dev/null

# load .env
set -a && source .env && set +a

if [ -z "$MMDEBSTRAP" ]; then MMDEBSTRAP=mmdebstrap; fi
if [ -z "$MIRROR" ]; then MIRROR=http://deb.debian.org; fi
_CODENAME="${CODENAME:-bookworm}"   # local default; don't export so output path stays plain when CODENAME unset
if [ -z "$NEOFETCH" ]; then
    if [ "${_CODENAME}" = "bookworm" ]; then NEOFETCH="neofetch"; else NEOFETCH="fastfetch"; fi
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
	"
if [ -z "$USER_PACKAGE" ]; then 
    # common packages I use that are not strictly necessary 
    USER_PACKAGE="build-essential libevent-dev libjpeg-dev libbsd-dev \
	    git pkg-config curl gpiod lm-sensors libgpiod-dev seatd mpv \
	    python3 python3-minimal python3-setuptools"
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

if [ -n "${CODENAME:-}" ]; then
    BASE_EXT4="./build/rootfs_base-${CODENAME}.ext4"
    BASE_EXT2="./build/rootfs_base-${CODENAME}.ext2"
else
    BASE_EXT4="./build/rootfs_base.ext4"
    BASE_EXT2="./build/rootfs_base.ext2"
fi

# Write sources list to a temp file so mmdebstrap can write directly to $MNT
# (avoids the stdin→tar pipe which fails with fuse2fs+fakeroot)
SOURCES=$(mktemp)
cat > "$SOURCES" << EOF
deb [trusted=yes] ${MIRROR}/debian/ ${_CODENAME} main contrib non-free non-free-firmware
deb [trusted=yes] ${MIRROR}/debian/ ${_CODENAME}-updates main contrib non-free non-free-firmware
EOF

# Resolve apt proxy: use APT_PROXY if set and reachable, else APT_PROXY_FALLBACK if set and reachable, else no proxy
proxy_reachable() {
    local url="$1"
    local host port
    host=$(echo "$url" | sed 's|.*://||; s|/.*||; s|:.*||')
    port=$(echo "$url" | sed 's|.*://||; s|/.*||; s|.*:||')
    [ -n "$host" ] && [ -n "$port" ] && bash -c "echo > /dev/tcp/${host}/${port}" 2>/dev/null
}
APT_PROXY_URL=""
if [ -n "${APT_PROXY:-}" ] && proxy_reachable "${APT_PROXY}"; then
    APT_PROXY_URL="${APT_PROXY}"
elif [ -n "${APT_PROXY_FALLBACK:-}" ] && proxy_reachable "${APT_PROXY_FALLBACK}"; then
    APT_PROXY_URL="${APT_PROXY_FALLBACK}"
fi

MMDEBSTRAP_OPTS=(
    ${APT_PROXY_URL:+--aptopt="Acquire::HTTP::Proxy \"${APT_PROXY_URL}\";"}
    --aptopt="Dir::Etc::Trusted \"$(pwd)/build/keyrings/debian-archive-keyring.gpg\""
    --architectures=arm64 -v -d
    --include="${BASE_PACKAGE} ${DESKTOP_PACKAGE} ${USER_PACKAGE}"
    # py3compile fails in cross-arch chroot (dpkg -L fails during configure).
    # Divert py3compile before python3 is installed so our stub survives package
    # extraction, then remove the diversion and reinstall to restore the real file.
    --essential-hook='chroot "$1" dpkg-divert --local --rename --add /usr/bin/py3compile && printf "#!/bin/sh\nexit 0\n" > "$1/usr/bin/py3compile" && chmod +x "$1/usr/bin/py3compile"'
    --customize-hook='rm -f "$1/usr/bin/py3compile" && chroot "$1" dpkg-divert --rename --remove /usr/bin/py3compile'
)

rm -f "$BASE_EXT2" "$BASE_EXT4"
$MMDEBSTRAP "${MMDEBSTRAP_OPTS[@]}" "$_CODENAME" "$BASE_EXT2" "$SOURCES"

rm "$SOURCES"
# Convert ext2 → ext4 (add journal and ext4 features)
tune2fs -O has_journal,extents,uninit_bg,dir_index,filetype,sparse_super "$BASE_EXT2"
e2label "$BASE_EXT2" lpi3h-root
e2fsck -fp "$BASE_EXT2" || [ $? -le 2 ]
mv "$BASE_EXT2" "$BASE_EXT4"

echo "mkrootfs done. Base image: $BASE_EXT4"

popd > /dev/null
