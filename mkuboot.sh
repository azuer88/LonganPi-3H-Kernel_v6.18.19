#!/usr/bin/env bash
pushd "$(dirname "$(realpath "$0")")" > /dev/null

mkdir -p build

if [ -z "$URL" ]
then
	export URL="https://github.com/u-boot/u-boot"
fi

if [ -z "$BRANCH" ]
then
	export BRANCH="master"
fi

if [ -z "$CROSS_COMPILE" ]
then
	export CROSS_COMPILE="aarch64-linux-gnu-"
fi

set -eux

if [ ! -e build/uboot ] 
then
	git clone $URL build/uboot --branch=${BRANCH}
	cd build/uboot
	git checkout v2026.04
	find ../../uboot/ -name *.patch | sort | while read line
	do
		git am < $line
	done
	cd ../../
fi

cd build/uboot
export ARCH=arm64
make clean
make longanpi_3h_defconfig
export BL31=$(pwd)/../bl31.bin
make -j$(nproc)
cp u-boot-sunxi-with-spl.bin ../

popd > /dev/null
