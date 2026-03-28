if [ -z "${MACID:-}" ]; then 
    echo "MACID not defined, will not do anything."
    exit -2 
fi
HOSTNAME="lpi3h-${MACID: -4}"
echo "Hostname: '$HOSTNAME'"
TARGET="/etc/hostname"
echo "Creating $TARGET in $1"
cat << EOF > "$1$TARGET"
${HOSTNAME}
EOF
TARGET="/etc/hosts"
echo "Appending $TARGET in $1"
cat << EOF >> "$1$TARGET"
127.0.0.1 $HOSTNAME
EOF

echo "Current dir: $(pwd)"

# ensure is owned by root
chown root:root "$1$TARGET"

echo "$0 done."
