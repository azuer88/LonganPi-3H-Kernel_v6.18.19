TARGET="/etc/default/console-setup"
echo "Creating $TARGET in $1"
cat << EOF > "$1$TARGET"
# CONFIGURATION FILE FOR SETUPCON

# Consult the console-setup(5) manual page.

ACTIVE_CONSOLES="/dev/tty[1-6]"

CHARMAP="ARMSCII-8"

CODESET="guess"
FONTFACE="Fixed"
FONTSIZE="8x18"

VIDEOMODE=

# The following is an example how to use a braille font
# FONT='lat9w-08.psf.gz brl-8x8.psf'
EOF

echo "Current dir: $(pwd)"

# ensure is owned by root
chown root:root "$1$TARGET"

echo "$0 done."
