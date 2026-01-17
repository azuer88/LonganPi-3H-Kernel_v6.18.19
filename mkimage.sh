#!/bin/bash

if [ ! -e ./build/rootfs.tar ]
then
    echo "./build/rootfs.tar not found"
    exit 1
fi

# load .env
set -a && source .env && set +a

set -eux

rm -rf build/rootfs
rm -rf build/input/
rm -rf build/root/
rm -rf build/tmp/
rm -rf build/images/
rm -rf build/sdcard.img
mkdir -pv build/rootfs
mkdir -pv build/input/
mkdir -pv build/tmp/
mkdir -pv build/root/
mkdir -pv build/images/

#C
IMAGE_BLOCKS=`du -k --block-size 500M build/rootfs.tar | cut -f1`
IMAGE_SIZE=$(( IMAGE_BLOCKS * 500 ))

cp -v ./build/u-boot-sunxi-with-spl.bin ./build/input/

dd if=/dev/zero of=./build/input/rootfs.ext4 bs=1M count=$IMAGE_SIZE

mkfs.ext4 -L lpi3h-root ./build/input/rootfs.ext4
mkdir -pv ./build/rootfs

if [ `id -u` -ne 0 ]
then
	fuse2fs -o fakeroot ./build/input/rootfs.ext4 ./build/rootfs
	fakeroot -- tar --numeric-owner -xpf build/rootfs.tar -C ./build/rootfs/
	echo "calling customization scripts"
	source ./customize_rootfs.sh ./build/rootfs
	echo "done with customization scripts"
	sudo umount ./build/rootfs
else
	mount ./build/input/rootfs.ext4 ./build/rootfs/
	tar --numeric-owner -xpf build/rootfs.tar -C ./build/rootfs/
	echo "calling customization scripts"
	source ./customize_rootfs.sh ./build/rootfs
	echo "done with customization scripts."
	umount ./build/rootfs
fi

echo "creating image..."

if [ -z "${IMAGE_NAME:-}" ]; then
    IMAGE_NAME="sdcard-$MACID"
fi 
cat << EOF > "build/genimage.cfg"
# Minimal SD card image for the Allwinner H618

image ${IMAGE_NAME}.img {
	hdimage {
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
EOF

cd ./build
genimage
cd ..

echo "compressing image..."
# requires pv to be installed 
pv build/images/${IMAGE_NAME}.img | xz -z > build/images/${IMAGE_NAME}.img.xz

rm -rf ./build/rootfs
