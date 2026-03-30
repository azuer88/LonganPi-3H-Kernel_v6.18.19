# DietPi Installer Post-Install Fixes — LonganPi 3H

After running the DietPi installer on the LonganPi 3H image, several things break
that require manual recovery via USB serial (`/dev/ttyUSB0` at 115200 baud).

---

## Problem 1: MBR disk signature overwritten (PARTUUID mismatch)

DietPi's `dietpi-drive_manager` rewrites the MBR disk signature at offset 440 with a
random value. This changes the PARTUUID, causing the kernel to hang at:

```
Waiting for root device PARTUUID=4c503348-01...
```

**Fix:** restore the correct signature from the host with the SD card mounted:

```sh
printf '\x48\x33\x50\x4c' | sudo dd bs=1 seek=440 of=/dev/sdX conv=notrunc
# Verify: should show 48 33 50 4c
sudo dd if=/dev/sdX bs=1 skip=440 count=4 2>/dev/null | xxd
```

Or from the running board (if it booted via extlinux fallback):

```sh
printf '\x48\x33\x50\x4c' | sudo dd bs=1 seek=440 of=/dev/mmcblk1 conv=notrunc
```

---

## Problem 2: No DHCP client installed

DietPi strips the DHCP client during installation. The `networking` service starts
successfully but `end0` stays DOWN because `ifup` finds no DHCP client.

**Workaround — assign a temporary static IP to get network:**

```sh
sudo ip link set end0 up
sudo ip addr add 192.168.254.200/24 dev end0
sudo ip route add default via 192.168.254.254 dev end0
echo "nameserver 192.168.254.254" | sudo tee /etc/resolv.conf
```

**Fix — install dhcpcd5:**

```sh
# Set apt proxy (if needed)
echo 'Acquire::http::Proxy "http://192.168.254.19:8000";' | sudo tee /etc/apt/apt.conf.d/01proxy

sudo apt-get update
sudo apt-get install -y dhcpcd5

# Remove temp static IP, dhcpcd will take over
sudo ip addr del 192.168.254.200/24 dev end0
sudo ip route del default

sudo systemctl enable --now dhcpcd
```

The interface (`end0`) will get a DHCP lease automatically on next boot and from now on.

---

## Problem 3: No SSH server installed

DietPi does not install `openssh-server` by default.

**Fix:**

```sh
sudo apt-get install -y openssh-server
```

SSH starts immediately after install and is enabled at boot.

---

## Recovery sequence (connect via serial first)

```sh
# 1. Bring up networking manually
sudo ip link set end0 up
sudo ip addr add 192.168.254.200/24 dev end0
sudo ip route add default via 192.168.254.254 dev end0
echo "nameserver 192.168.254.254" | sudo tee /etc/resolv.conf

# 2. Set apt proxy
echo 'Acquire::http::Proxy "http://192.168.254.19:8000";' | sudo tee /etc/apt/apt.conf.d/01proxy

# 3. Install missing packages
sudo apt-get update
sudo apt-get install -y dhcpcd5 openssh-server

# 4. Clean up temp static IP
sudo ip addr del 192.168.254.200/24 dev end0
sudo ip route del default 2>/dev/null || true

# 5. Start services
sudo systemctl enable --now dhcpcd
# openssh-server starts automatically on install

# 6. Restore MBR disk signature (if board is not booting from extlinux fallback)
#    Run from host with SD card at /dev/sdX:
#    printf '\x48\x33\x50\x4c' | sudo dd bs=1 seek=440 of=/dev/sdX conv=notrunc
```

---

## Notes

- The apt proxy `192.168.254.19:8000` is a local squid-deb-proxy. It blocks
  `dietpi.com` (403 Forbidden) but allows Debian repos — `apt update` will show
  warnings for the DietPi repo but Debian packages install fine.
- `end0` is the board's ethernet interface (emac1, `dwmac-sun8i`).
- Serial console: `/dev/ttyUSB0` at 115200 baud on the build host.
- After DietPi installer, the hostname may be reset to `localhost`. DietPi sets it
  to `DietPi` on first full boot via `dietpi-login`.
