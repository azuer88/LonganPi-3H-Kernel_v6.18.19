#!/bin/bash
# Copy base ext4, apply customization scripts, produce build/input/rootfs.ext4
# Usage: bash mkcustomrootfs.sh
#
# Requires: build/rootfs_base.ext4 (created by mkrootfs.sh)

if [ $(id -u) -ne 0 ]; then
    exec sudo "$(realpath $0)" "$@"
fi

BASE_EXT4="./build/rootfs_base.ext4"
if [ ! -e "$BASE_EXT4" ]; then
    echo "build/rootfs_base.ext4 not found — run mkrootfs.sh first"
    exit 1
fi

# load .env
set -a && source .env && set +a

set -eux

rm -rf build/rootfs build/input/ build/root/ build/tmp/ build/sdcard.img
mkdir -pv build/input/ build/tmp/ build/root/ build/images/

cp -v ./build/u-boot-sunxi-with-spl.bin ./build/input/

# Sparse copy — fast on any filesystem; instant with reflinks (btrfs/xfs)
echo "Copying base ext4..."
cp --sparse=always --reflink=auto "$BASE_EXT4" ./build/input/rootfs.ext4

mkdir -pv ./build/rootfs

# Create a 63 MB FAT32 boot partition image containing the kernel, DTB, and
# extlinux/extlinux.conf. U-Boot reads from this partition (mmc 0:1) using its
# FAT driver, which avoids the ext4 block-group > 3 limitation.
make_boot_fat() {
    local ROOTFS="$1"
    local BOOT_FAT="./build/input/boot.fat"
    local BOOT_PARTUUID="4c503348-02"   # rootfs is partition 2

    local KVER
    KVER=$(ls "$ROOTFS/boot/vmlinuz-"* 2>/dev/null | head -1 | sed "s|.*/vmlinuz-||")
    if [ -z "$KVER" ]; then
        echo "ERROR: make_boot_fat: no kernel found in $ROOTFS/boot" >&2
        exit 1
    fi

    local DTB_SRC="$ROOTFS/usr/lib/linux-image-${KVER}/allwinner/sun50i-h618-longanpi-3h.dtb"
    if [ ! -f "$DTB_SRC" ]; then
        echo "ERROR: make_boot_fat: DTB not found at $DTB_SRC" >&2
        exit 1
    fi

    echo "Creating boot FAT partition (kernel=${KVER})..."
    truncate -s 63M "$BOOT_FAT"
    mkfs.fat -F 32 -n lpi3h-boot "$BOOT_FAT"
    mmd -i "$BOOT_FAT" "::extlinux"
    mcopy -i "$BOOT_FAT" "$ROOTFS/boot/vmlinuz-${KVER}" "::vmlinuz-${KVER}"
    mcopy -i "$BOOT_FAT" "$DTB_SRC" "::sun50i-h618-longanpi-3h.dtb"

    # Write extlinux.conf with paths relative to FAT partition root
    local TMP_CONF
    TMP_CONF=$(mktemp)
    cat > "$TMP_CONF" << EOF
timeout 30
default l0

label l0
    kernel /vmlinuz-${KVER}
    fdt /sun50i-h618-longanpi-3h.dtb
    append root=PARTUUID=${BOOT_PARTUUID} rootfstype=ext4 rootwait console=tty0 console=ttyS0,115200 earlycon clk_ignore_unused rw video=HDMI-A-1:1280x720@60
EOF
    mcopy -i "$BOOT_FAT" "$TMP_CONF" "::extlinux/extlinux.conf"
    rm -f "$TMP_CONF"
    echo "boot FAT created: $BOOT_FAT"
}

if [ $(id -u) -ne 0 ]; then
    fuse2fs ./build/input/rootfs.ext4 ./build/rootfs
    echo "calling customization scripts"
    source ./customize_rootfs.sh ./build/rootfs
    echo "done with customization scripts"
    make_boot_fat ./build/rootfs
    fusermount -u ./build/rootfs
else
    mount ./build/input/rootfs.ext4 ./build/rootfs/
    echo "calling customization scripts"
    source ./customize_rootfs.sh ./build/rootfs
    echo "done with customization scripts."
    make_boot_fat ./build/rootfs
    umount ./build/rootfs
fi

e2fsck -fp build/input/rootfs.ext4
BLKSIZE=$(tune2fs -l build/input/rootfs.ext4 | awk '/^Block size/{print $3}')
MIN_BLOCKS=$(resize2fs -P build/input/rootfs.ext4 2>/dev/null | awk '{print $NF}')
EXTRA_BLOCKS=$(( 500 * 1024 * 1024 / BLKSIZE ))
resize2fs build/input/rootfs.ext4 $(( MIN_BLOCKS + EXTRA_BLOCKS ))

rm -rf ./build/rootfs

echo "mkcustomrootfs done. rootfs.ext4 ready at build/input/rootfs.ext4"
