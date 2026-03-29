# AUTHORIZED_KEY=  defined in .env
# USER_NAME= defined in .env

mkdir -p "$1/home/$USER_NAME/.ssh"
chmod 0700 "$1/home/$USER_NAME/.ssh"

echo "creating $USER_NAME/.ssh/authorized_keys"
cat << EOF > "$1/home/$USER_NAME/.ssh/authorized_keys"
$AUTHORIZED_KEY

EOF
chmod 0600 "$1/home/$USER_NAME/.ssh/authorized_keys"

echo "changing ownership"
# Get UID/GID from rootfs passwd rather than --reference (home dir may be empty)
U_UID=$(grep "^${USER_NAME}:" "$1/etc/passwd" | cut -d: -f3)
U_GID=$(grep "^${USER_NAME}:" "$1/etc/passwd" | cut -d: -f4)
if [ -n "$U_UID" ] && [ -n "$U_GID" ]; then
    chown -R "$U_UID:$U_GID" "$1/home/$USER_NAME/.ssh"
else
    echo "Warning: could not find UID/GID for $USER_NAME in rootfs, skipping chown"
fi

echo "$0 done."
