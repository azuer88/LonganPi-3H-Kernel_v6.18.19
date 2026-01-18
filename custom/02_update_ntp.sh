TIMESYNCD_CONF="/etc/systemd/timesyncd.conf"

if [ -n "$NTP_SERVER" ]; then
    sed -i.bak -e "/\[Time\]/a NTP=$NTP_SERVER" "$1${TIMESYNCD_CONF}"
else
    echo "NTP_SERVER not set, will not do anything."
fi

if [ -n "$TIMEZONE" ]; then
    ln -s /etc/localtime ../usr/share/zoneinfo/$TIMEZONE
else
    echo "TIMEZONE not set, will not do anything.

echo "*** $TIMESYNCD_CONF ***"
cat "$1$TIMESYNCD_CONF"
echo "***********************"

echo "$0 done."
