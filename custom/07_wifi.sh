# SSID=  load from .env (in mkrootfs.sh)
# PKEY=  load from .env 
if [ -z "${SSID:-}" ]; then 
    echo "SSID not defined, will not do anything."
    exit -1
fi
if [ -z "${MACID:-}" ]; then 
    echo "MACID not defined, will not do anything."
    exit -2 
fi
if [ -z "${PKEY:-}" ]; then
    echo "PKEY not defined, will not do anything."
    exit -3
fi
TARGET="/etc/NetworkManager/system-connections/$SSID.nmconnection"
echo "Creating $TARGET in $1"
umask 077
# uuidgen may be absent in some build environments; fall back to /proc/sys/kernel/random/uuid
_UUID=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)
cat << EOF > "$1$TARGET"
[connection]
id=$SSID
uuid=${_UUID}
type=wifi
interface-name=wlx${MACID}

[wifi]
mode=infrastructure
ssid=$SSID

[wifi-security]
auth-alg=open
key-mgmt=wpa-psk
psk=$PKEY

[ipv4]
method=auto

[ipv6]
addr-gen-mode=default
method=auto

[proxy]

EOF

# ensure connection is owned by root
chown root:root "$1$TARGET"

echo "$0 done."
