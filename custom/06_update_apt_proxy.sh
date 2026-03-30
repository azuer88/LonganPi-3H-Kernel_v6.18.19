
# Remove the proxy file mmdebstrap leaves behind — it's build-host-only
rm -f "$1/etc/apt/apt.conf.d/99mmdebstrap"

if [ -n "${APT_PROXY:-}" ]; then
    PROXYFILE="/etc/apt/apt.conf.d/02Proxy"
    cat << EOF > "$1${PROXYFILE}"
Acquire::HTTP::Proxy "$APT_PROXY";

EOF
    cat "$1${PROXYFILE}"
    chown root:root "$1${PROXYFILE}"
else
    echo "APT_PROXY is not defined.  Not doing anything."
fi

echo "$0 done."
