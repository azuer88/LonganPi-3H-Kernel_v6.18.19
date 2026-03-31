#!/bin/bash
# Create SD card .img from build/input/rootfs.ext4 + u-boot, then compress
# Usage: bash mksdimg.sh

# load .env (needed for CODENAME)
set -a && source .env && set +a

if [ -n "${CODENAME:-}" ] && [ -e "./build/input/rootfs-${CODENAME}.ext4" ]; then
    ROOTFS_FILE="rootfs-${CODENAME}.ext4"
else
    if [ -n "${CODENAME:-}" ]; then
        echo "WARNING: build/input/rootfs-${CODENAME}.ext4 not found — falling back to rootfs.ext4"
    fi
    ROOTFS_FILE="rootfs.ext4"
fi

if [ ! -e "./build/input/$ROOTFS_FILE" ]; then
    echo "./build/input/$ROOTFS_FILE not found — run mkcustomrootfs.sh first"
    exit 1
fi

if [ ! -e ./build/input/u-boot-sunxi-with-spl.bin ]; then
    echo "./build/input/u-boot-sunxi-with-spl.bin not found — run mkcustomrootfs.sh first"
    exit 1
fi

if [ ! -e ./build/input/boot.fat ]; then
    echo "./build/input/boot.fat not found — run mkcustomrootfs.sh first"
    exit 1
fi

set -eux

if [ -z "${IMAGE_NAME:-}" ]; then
    IMAGE_NAME="sdcard-$MACID"
    if [ -n "${CODENAME:-}" ]; then
        IMAGE_NAME="${IMAGE_NAME}-${CODENAME}"
    fi
fi

if [ "${NOGUI:-1}" = "0" ]; then
    IMAGE_NAME="${IMAGE_NAME}-GUI"
fi

# Fixed MBR disk signature so PARTUUIDs are stable across flashes.
# Partition 1 (FAT boot):  PARTUUID=4c503348-01
# Partition 2 (ext4 root): PARTUUID=4c503348-02
DISK_SIGNATURE="4c503348"

echo "creating image..."

cat << GENEOF > "build/genimage.cfg"
# Minimal SD card image for the Allwinner H618

image ${IMAGE_NAME}.img {
	hdimage {
		disk-signature = 0x${DISK_SIGNATURE}
	}

	partition u-boot {
		in-partition-table = false
		image = "u-boot-sunxi-with-spl.bin"
		offset = 8K
	}

	partition boot {
		partition-type = 0x0c
		image = "boot.fat"
		offset = 1M
	}

	partition rootfs {
		partition-type = 0x83
		image = "${ROOTFS_FILE}"
		offset = 64M
	}
}
GENEOF

cd ./build
genimage
cd ..

echo "compressing image..."
xz -z -T 0 -7 -f --verbose "build/images/${IMAGE_NAME}.img"

echo "mksdimg done. Image at build/images/${IMAGE_NAME}.img.xz"
