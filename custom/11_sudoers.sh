#!/usr/bin/env bash
# Install passwordless sudo for USER_NAME if NOPASS_SUDO=1
# $1 = target rootfs directory

if [ "${NOPASS_SUDO:-0}" != "1" ]; then
    echo "NOPASS_SUDO not set to 1, skipping."
    exit 0
fi

if [ -z "${USER_NAME:-}" ]; then
    echo "USER_NAME not defined, skipping."
    exit 0
fi

SUDOERS_FILE="$1/etc/sudoers.d/50-${USER_NAME}-nopasswd"
echo "Writing $SUDOERS_FILE"
install -m 0440 /dev/null "$SUDOERS_FILE"
echo "${USER_NAME} ALL=(ALL) NOPASSWD:ALL" > "$SUDOERS_FILE"

echo "$0 done."
