#!/bin/bash
# Build the LPI3H kernel from an already-patched tree.
# Usage: bash mkkernel.sh [--clean]
#
# Options:
#   --clean   Run 'make clean' before building (slower but safe after config changes)
#
# Environment overrides:
#   LINUX_DIR     Path to kernel source tree (default: ./build/linux)
#   CROSS_COMPILE Cross compiler prefix     (default: aarch64-linux-gnu-)
#   JOBS          Parallel jobs             (default: nproc)
#   CONFIG        Defconfig name            (default: longanpi_3h_defconfig)

set -euo pipefail

LINUX_DIR="${LINUX_DIR:-$(dirname "$0")/build/linux}"
CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
JOBS="${JOBS:-$(nproc)}"
CONFIG="${CONFIG:-longanpi_3h_defconfig}"
CLEAN=0

for arg in "$@"; do
    case "$arg" in
        --clean) CLEAN=1 ;;
        *) echo "Unknown argument: $arg"; exit 1 ;;
    esac
done

if [ ! -d "$LINUX_DIR" ]; then
    echo "Kernel source not found at $LINUX_DIR"
    exit 1
fi

cd "$LINUX_DIR"

MAKE="make ARCH=arm64 CROSS_COMPILE=${CROSS_COMPILE} -j${JOBS}"

echo "=== Kernel build ==="
echo "  Source : $LINUX_DIR"
echo "  Config : $CONFIG"
echo "  Jobs   : $JOBS"
echo "  Clean  : $CLEAN"
echo ""

if [ "$CLEAN" -eq 1 ]; then
    echo "--- make clean ---"
    make ARCH=arm64 CROSS_COMPILE=${CROSS_COMPILE} clean
fi

echo "--- make $CONFIG ---"
make ARCH=arm64 CROSS_COMPILE=${CROSS_COMPILE} "$CONFIG"

echo "--- make bindeb-pkg ---"
$MAKE bindeb-pkg

echo ""
echo "=== Done ==="
ls -lh "$(dirname "$LINUX_DIR")"/*.deb 2>/dev/null || true
