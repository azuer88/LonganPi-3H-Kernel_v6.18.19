#!/bin/bash

CURDIR="$(dirname "$(realpath "$0")")"
docker run --rm --network=host --ulimit nofile=1048576:1048576 --cpus="10" \
    -v $CURDIR:/sdk lpi3h-build \
    bash -c "cd /sdk && CROSS_COMPILE=aarch64-linux-gnu- bash $@"
sudo chown $USER:$USER -R "${CURDIR}/build"
