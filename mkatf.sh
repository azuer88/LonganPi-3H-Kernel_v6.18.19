#!/usr/bin/env bash
pushd "$(dirname "$(realpath "$0")")" > /dev/null

mkdir -p build 


if [ -z "$URL" ]
then
	export URL="https://github.com/ARM-software/arm-trusted-firmware"
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

if [ ! -e build/arm-trusted-firmware ] 
then
	git clone $URL build/arm-trusted-firmware --branch=${BRANCH}
	cd build/arm-trusted-firmware
	git checkout 5e52433dd6794aa5c2186a990cb7f4dfa6f2ef01
	cd ../../
fi

cd build/arm-trusted-firmware
make clean
rm -rf ./build
make PLAT=sun50i_h616 bl31

cd ../../
chown $UID:$UID -R build/arm-trusted-firmware
cp build/arm-trusted-firmware/build/sun50i_h616/release/bl31.bin build/

popd > /dev/null

