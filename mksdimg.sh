#!/bin/bash
# Create SD card .img from build/input/rootfs.ext4 + u-boot, then compress
# Usage: bash mksdimg.sh

if [ ! -e ./build/input/rootfs.ext4 ]; then
    echo "./build/input/rootfs.ext4 not found — run mkcustomrootfs.sh first"
    exit 1
fi

if [ ! -e ./build/input/u-boot-sunxi-with-spl.bin ]; then
    echo "./build/input/u-boot-sunxi-with-spl.bin not found — run mkcustomrootfs.sh first"
    exit 1
fi

# load .env
set -a && source .env && set +a

set -eux

if [ -z "${IMAGE_NAME:-}" ]; then
    IMAGE_NAME="sdcard-$MACID"
fi

# Fixed MBR disk signature so PARTUUID is stable across flashes.
# PARTUUID for rootfs partition = 4c503348-01
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

	partition rootfs {
		partition-type = 0x83
		image = "rootfs.ext4"
		offset = 8M
	}
}
GENEOF

cd ./build
genimage
cd ..

echo "compressing image..."
xz -z -T 0 -7 -f --verbose "build/images/${IMAGE_NAME}.img"

echo "mksdimg done. Image at build/images/${IMAGE_NAME}.img.xz"
