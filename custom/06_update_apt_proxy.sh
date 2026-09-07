
# Remove the proxy file mmdebstrap leaves behind — it's build-host-only
rm -f "$1/etc/apt/apt.conf.d/99mmdebstrap"

# Force IPv4 for apt — some mirrors (deb.debian.org, apt.undo.it) 403 over
# IPv6 on this network, which otherwise silently breaks `apt-get update`/
# `install` on the board without an explicit -o Acquire::ForceIPv4=true.
cat << EOF > "$1/etc/apt/apt.conf.d/99force-ipv4"
Acquire::ForceIPv4 "true";
EOF
chown root:root "$1/etc/apt/apt.conf.d/99force-ipv4"

proxy_reachable() {
    local url="$1"
    local host port
    host=$(echo "$url" | sed 's|.*://||; s|/.*||; s|:.*||')
    port=$(echo "$url" | sed 's|.*://||; s|/.*||; s|.*:||')
    [ -n "$host" ] && [ -n "$port" ] && bash -c "echo > /dev/tcp/${host}/${port}" 2>/dev/null
}

if [ -n "${APT_PROXY:-}" ] && proxy_reachable "${APT_PROXY}"; then
    PROXYFILE="/etc/apt/apt.conf.d/02Proxy"
    cat << EOF > "$1${PROXYFILE}"
Acquire::HTTP::Proxy "${APT_PROXY}";

EOF
    cat "$1${PROXYFILE}"
    chown root:root "$1${PROXYFILE}"
else
    echo "APT_PROXY is not set or not reachable. Not writing proxy config."
fi

echo "$0 done."
