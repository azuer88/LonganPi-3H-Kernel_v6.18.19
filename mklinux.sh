#!/bin/bash
# Download Linux 6.18.19 and apply LPI3H patches.
# Produces build/linux — a patched kernel source tree ready for mkkernel.sh.
#
# Usage: bash mklinux.sh [--force]
#
# Options:
#   --force   Delete build/linux and re-clone/re-patch from scratch
#
# Environment overrides:
#   LINUX_DIR      Destination path (default: ./build/linux)
#   LINUX_URL      Kernel git URL (default: kernel.org stable tree)
#   PATCHES_DIR    Patch directory  (default: ./kernel_patches)
#   BASE_COMMIT    Base commit to check out (default: 4aea1dc4c)
#   BASE_TAG       Tag for shallow clone   (default: v6.18.19)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load .env as defaults; existing environment variables take precedence
if [ -f "$SCRIPT_DIR/.env" ]; then
    while IFS='=' read -r key rest; do
        [[ "$key" =~ ^[[:space:]]*# || -z "${key// }" ]] && continue
        [[ -v "$key" ]] || export "$key=$rest"
    done < "$SCRIPT_DIR/.env"
fi

LINUX_DIR="${LINUX_DIR:-$SCRIPT_DIR/build/linux}"
LINUX_URL="${LINUX_URL:-https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git}"
PATCHES_DIR="${PATCHES_DIR:-$SCRIPT_DIR/kernel_patches}"
BASE_COMMIT="${BASE_COMMIT:-4aea1dc4c}"
BASE_TAG="${BASE_TAG:-v6.18.19}"
FORCE=0

for arg in "$@"; do
    case "$arg" in
        --force) FORCE=1 ;;
        *) echo "Unknown argument: $arg"; exit 1 ;;
    esac
done

echo "=== mklinux: prepare kernel source ==="
echo "  Destination : $LINUX_DIR"
echo "  URL         : $LINUX_URL"
echo "  Base tag    : $BASE_TAG ($BASE_COMMIT)"
echo "  Patches     : $PATCHES_DIR"
echo ""

if [ "$FORCE" -eq 1 ] && [ -d "$LINUX_DIR" ]; then
    echo "--- --force: removing existing $LINUX_DIR ---"
    rm -rf "$LINUX_DIR"
fi

if [ -d "$LINUX_DIR" ]; then
    echo "--- build/linux already exists, skipping clone/patch ---"
    echo "    Use --force to re-clone from scratch."
    exit 0
fi

mkdir -p "$(dirname "$LINUX_DIR")"

echo "--- cloning $BASE_TAG (shallow) ---"
git clone --depth 1 --branch "$BASE_TAG" "$LINUX_URL" "$LINUX_DIR"

cd "$LINUX_DIR"

# Verify we're on the expected base commit
ACTUAL=$(git rev-parse --short HEAD)
if [[ "$ACTUAL" != "${BASE_COMMIT:0:${#ACTUAL}}" ]]; then
    echo "ERROR: expected base commit $BASE_COMMIT, got $ACTUAL"
    exit 1
fi
echo "  Base commit verified: $ACTUAL"

# Apply patches in order
PATCHES=("$PATCHES_DIR"/[0-9]*.patch)
if [ ${#PATCHES[@]} -eq 0 ]; then
    echo "ERROR: no patches found in $PATCHES_DIR"
    exit 1
fi

echo ""
echo "--- applying ${#PATCHES[@]} patches ---"
for patch in "${PATCHES[@]}"; do
    name="$(basename "$patch")"
    echo "  $name"
    git am --3way < "$patch"
done

# Copy out-of-tree BSP drivers into the kernel source tree
echo ""
echo "--- copying bsp/ into kernel source ---"
cp -raf "$SCRIPT_DIR/bsp" "$LINUX_DIR/"

echo ""
echo "=== Done ==="
echo "  HEAD: $(git rev-parse --short HEAD)"
echo "  Patches applied: ${#PATCHES[@]}"
echo "  Ready for: bash mkkernel.sh"
