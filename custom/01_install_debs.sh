#!/usr/bin/env bash
# Install overlay.deb and kernel debs into rootfs.
# Uses dpkg-deb --extract (fakeroot-compatible; does not run postinst scripts).
# Kernel debs are only installed if newer than what is in the rootfs.
# $1 = target rootfs directory

ROOTFS="$1"
BUILD="./build"

# Repair merged-usr: if /lib was replaced by a real directory (dpkg-deb --extract
# does not follow symlinks when creating directories), move its contents to usr/lib
# and restore the /lib -> usr/lib symlink.
repair_merged_usr() {
    if [ -d "$ROOTFS/lib" ] && [ ! -L "$ROOTFS/lib" ]; then
        echo "Repairing merged-usr: /lib symlink was replaced, restoring"
        cp -a "$ROOTFS/lib/." "$ROOTFS/usr/lib/"
        rm -rf "$ROOTFS/lib"
        ln -s usr/lib "$ROOTFS/lib"
    fi
}

# --- overlay.deb ---
if [ -f "$BUILD/overlay.deb" ]; then
    echo "Extracting overlay.deb"
    dpkg-deb --extract "$BUILD/overlay.deb" "$ROOTFS"
    repair_merged_usr
    echo "overlay.deb installed"
else
    echo "overlay.deb not found, skipping"
fi

# --- kernel debs (latest by mtime) ---
# Only install if the rootfs does not already have the same kernel version.
LATEST_IMAGE=$(ls -t "$BUILD"/linux-image-*.deb 2>/dev/null | head -1)
if [ -n "$LATEST_IMAGE" ]; then
    DEB_VER=$(dpkg-deb -f "$LATEST_IMAGE" Version)
    ROOTFS_VER=$(ls "$ROOTFS/boot/vmlinuz-"* 2>/dev/null | head -1 | sed "s|.*/vmlinuz-||")
    if [ "$ROOTFS_VER" = "$DEB_VER" ] || [ "$ROOTFS_VER" = "${DEB_VER%%+*}+" ]; then
        echo "Kernel $DEB_VER already in rootfs, skipping kernel debs"
    else
        echo "Installing kernel $DEB_VER (rootfs has: $ROOTFS_VER)"
        dpkg-deb --extract "$LATEST_IMAGE" "$ROOTFS"
        repair_merged_usr
        HEADERS_DEB=$(ls -t "$BUILD"/linux-headers-*.deb 2>/dev/null | head -1)
        if [ -f "$HEADERS_DEB" ]; then
            dpkg-deb --extract "$HEADERS_DEB" "$ROOTFS"
            repair_merged_usr
        fi
        echo "Kernel debs extracted"
    fi
else
    echo "No kernel debs found, skipping"
fi

echo "$0 done."
