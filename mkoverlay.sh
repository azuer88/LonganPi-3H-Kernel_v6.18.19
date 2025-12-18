#!/usr/bin/env bash

if [ ! -e build ]; then
    mkdir build
fi

set -eux

dpkg-deb --root-owner-group --build overlay
mv overlay.deb ./build/
