#!/bin/bash
# Usage: bash run_docker.sh [--privileged] <script.sh> [args...]

CURDIR="$(dirname "$(realpath "$0")")"

EXTRA_FLAGS=""
if [ "${1:-}" = "--privileged" ]; then
    EXTRA_FLAGS="--privileged"
    shift
fi

CPUS=$(( $(nproc) > 3 ? $(nproc) - 2 : 2 ))

docker run --rm --network=host --ulimit nofile=1048576:1048576 --cpus="$CPUS" \
    $EXTRA_FLAGS \
    -v "$CURDIR":/sdk lpi3h-build \
    bash -c "cd /sdk && CROSS_COMPILE=aarch64-linux-gnu- bash $*"
sudo chown "$USER":"$USER" -R "${CURDIR}/build"
