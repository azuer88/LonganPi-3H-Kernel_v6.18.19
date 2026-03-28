#!/usr/bin/env bash
# Run all executable scripts in ./custom/ against the rootfs mount point.
# Called by mkcustomrootfs.sh and mktestcustom.sh with the mount path as $1.

set -a && source .env && set +a

SCRIPTS="./custom"
PATTERN="*.sh"

for file in $SCRIPTS/$PATTERN; do
    if [ -f "$file" ] && [ -r "$file" ] && [ -x "$file" ]; then
        if [ "$(id -u)" -ne 0 ]; then
            echo "Executing $file as fakeroot"
            fakeroot -u -- bash "$file" "$1"
        else
            echo "Executing $file as root"
            bash "$file" "$1"
        fi
    else
        echo "skipped: $file"
    fi
done
