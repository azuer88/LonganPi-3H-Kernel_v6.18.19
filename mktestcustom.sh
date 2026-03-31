#!/bin/bash
# Fast test harness for customize_rootfs.sh custom scripts.
# Uses fuse-overlayfs with a plain-dir lower layer (extracted from rootfs_base.ext4).
# The base dir is cached — re-extracted only when rootfs_base.ext4 changes.
#
# Dirs:
#   build/rootfs_base/     — plain dir lower layer (cached extract from rootfs_base.ext4)
#   build/rootfs_upper/    — RW upper layer (cleared each run; shows what changed)
#   build/rootfs_work/     — overlayfs work dir (cleared each run)
#   build/rootfs/          — merged view (where custom scripts run)
#
# Usage:
#   bash mktestcustom.sh           # run custom scripts on overlay
#   bash mktestcustom.sh --reset   # force re-extract base from rootfs_base.ext4
pushd "$(dirname "$(realpath "$0")")" > /dev/null


BASE_EXT4="./build/rootfs_base.ext4"
if [ ! -e "$BASE_EXT4" ]; then
    echo "build/rootfs_base.ext4 not found — run mkrootfs.sh first"
    exit 1
fi

# load .env
set -a && source .env && set +a

set -eux

RESET=0
for arg in "$@"; do [ "$arg" = "--reset" ] && RESET=1; done

BASE="./build/rootfs_base"
UPPER="./build/rootfs_upper"
WORK="./build/rootfs_work"
MERGED="./build/rootfs"
MNT="./build/rootfs_ext4_mnt"

# Unmount stale mounts
fusermount -u "$MERGED" 2>/dev/null || true

# Populate plain-dir base layer (once, or on --reset / ext4 newer than base)
if [ $RESET -eq 1 ] || [ ! -d "$BASE/etc" ] || [ "$BASE_EXT4" -nt "$BASE" ]; then
    echo "=== Extracting base from rootfs_base.ext4 ==="
    rm -rf "$BASE"
    mkdir -p "$BASE" "$MNT"
    fuse2fs -o fakeroot "$BASE_EXT4" "$MNT"
    fakeroot -- bash -c "tar --numeric-owner -C '$MNT' -cpf - . | tar --numeric-owner -xpf - -C '$BASE'"
    fusermount -u "$MNT"
    rmdir "$MNT"
    touch "$BASE"
else
    echo "=== Base layer up to date, skipping extraction ==="
fi

# Fresh upper/work/merged each run
rm -rf "$UPPER" "$WORK"
mkdir -p "$UPPER" "$WORK" "$MERGED"

# Mount overlay
echo "=== Mounting fuse-overlayfs ==="
fuse-overlayfs \
    -o lowerdir="$BASE",upperdir="$UPPER",workdir="$WORK" \
    "$MERGED"

# Run customization scripts
echo "=== Running customization scripts ==="
source ./customize_rootfs.sh "$MERGED"
echo "=== Done ==="

fusermount -u "$MERGED"

popd > /dev/null 

echo "mktestcustom done. Inspect build/rootfs_upper/ for changes."
