
if [ -n "${APT_PROXY:-}" ]; then
    PROXYFILE="/etc/apt/apt.conf.d/02Proxy"
    cat << EOF > "$1${PROXYFILE}"
Acquire::HTTP::Proxy "$APT_PROXY";

EOF
    cat "$1${PROXYFILE}"
else
    echo "APT_PROXY is not defined.  Not doing anything."
fi
# ensure it is owned by root
chown root:root "$1${PROXYFILE}"

echo "$0 done."
