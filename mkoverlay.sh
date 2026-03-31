#!/usr/bin/env bash
pushd "$(dirname "$(realpath "$0")")" > /dev/null

if [ ! -e build ]; then
    mkdir build
fi

set -eux

dpkg-deb --root-owner-group --build overlay
mv overlay.deb ./build/

popd > /dev/null

