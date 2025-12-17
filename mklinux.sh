#!/usr/bin/env bash

mkdir -p build

if [ -z "$URL" ]
then
	export URL="https://github.com/torvalds/linux.git"
fi

if [ -z "$COMMIT" ]
then
	# export COMMIT="3b47bc037bd44f142ac09848e8d3ecccc726be99" # 6.7.0-rc3 
	export COMMIT="7d0a66e4bb9081d75c82ec4957c50034cb0ea449"  # 6.18

fi

if [ -z "$CROSS_COMPILE" ]
then
	export CROSS_COMPILE="aarch64-linux-gnu-"
fi

if [ -z "$CONFIG" ]
then
	export CONFIG="longanpi_3h_defconfig"
fi

set -eux

if [ ! -e build/linux ] 
then
	mkdir build/linux
	cd build/linux
	git init .
	git remote add origin "${URL}"
	git fetch origin "${COMMIT}" --depth=1
	git checkout "${COMMIT}"
	find ../../linux/ -name *.patch | sort | while read line
	do
		echo "$line" >> ../../patch.log
		git am < $line
	done
	cd ../../
fi

# add allwinner bsp support
if [ ! -e build/linux/bsp ]
then
	cp -raf bsp build/linux
fi

cd build/linux
export ARCH=arm64
rm -rf ../linux-*.deb
make mrproper
make $CONFIG
make -j$(nproc)
make deb-pkg
