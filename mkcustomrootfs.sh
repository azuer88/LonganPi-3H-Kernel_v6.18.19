#!/bin/bash
# Copy base ext4, apply customization scripts, produce build/input/rootfs.ext4
# Usage: bash mkcustomrootfs.sh
#
# Requires: build/rootfs_base.ext4 (created by mkrootfs.sh)

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

if [ $(id -u) -ne 0 ]; then
    fuse2fs -o fakeroot ./build/input/rootfs.ext4 ./build/rootfs
    echo "calling customization scripts"
    source ./customize_rootfs.sh ./build/rootfs
    echo "done with customization scripts"
    fusermount -u ./build/rootfs
else
    mount ./build/input/rootfs.ext4 ./build/rootfs/
    echo "calling customization scripts"
    source ./customize_rootfs.sh ./build/rootfs
    echo "done with customization scripts."
    umount ./build/rootfs
fi

e2fsck -fp build/input/rootfs.ext4
resize2fs -M build/input/rootfs.ext4

rm -rf ./build/rootfs

echo "mkcustomrootfs done. rootfs.ext4 ready at build/input/rootfs.ext4"
