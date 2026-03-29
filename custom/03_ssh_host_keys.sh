if [ -z "${MACID:-}" ]; then 
    echo "MACID not defined, will not do anything."
    exit -2 
fi

if [ ! -e build/host_keys/$MACID ]; then 
	mkdir -p build/host_keys/$MACID/etc/ssh 
        ssh-keygen -A -f build/host_keys/$MACID 
fi 

mkdir -p "$1/etc/ssh"
cp build/host_keys/$MACID/etc/ssh/ssh_host_* "$1/etc/ssh"

echo "Current dir: $(pwd)"

# ensure is owned by root
chown root:root "$1"/etc/ssh/ssh_host_*

echo "$0 done."
