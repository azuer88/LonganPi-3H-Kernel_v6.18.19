# tty1 btop Display Runbook — LonganPi 3H

## Context

This documents a setup found live on `lpi3h-f1a0`: `tty1` (the local HDMI/
console VT) runs `btop` full-screen instead of a login prompt, via a
`btop-display.service` unit that conflicts with `getty@tty1.service`. It was
installed by hand on that board — it is **not** part of `overlay/` or any
`custom/NN_*.sh` script, so it does not exist on freshly-built images. This
is the procedure to reproduce it on another board.

`btop` itself is already installed on every image (`mkrootfs.sh` includes it
in the base package list), so this only adds the display service and a
console font.

---

## 0. Prerequisite: disable AICWFDBG driver logging

The `aic8800_fdrv` WiFi driver defaults to `aicwf_dbg_level=3`
(`LOGERROR|LOGINFO`), which prints `AICWFDBG(...)` lines via `printk` — these
land on the console and, on a board using `console=tty1` (or wherever the
kernel console is routed to the local VT), tear straight through btop's
full-screen framebuffer output. Confirm and fix before installing the
display service, not after — noisy driver logs are hard to notice once
btop is already redrawing over them:

```sh
ssh <board> 'cat /sys/module/aic8800_fdrv/parameters/aicwf_dbg_level'
# should read 0; if not:
ssh <board> 'echo 0 | sudo tee /sys/module/aic8800_fdrv/parameters/aicwf_dbg_level'
```

That only takes effect until the next module reload/reboot. Persist it with
`overlay/etc/modprobe.d/aic8800_fdrv.conf` (`options aic8800_fdrv
aicwf_dbg_level=0`, added in commit `d83d9ef`) — this ships in `overlay.deb`
on every fresh image, but a board that hasn't been reflashed/updated since
that commit needs the file installed by hand:

```sh
ssh <board> 'sudo tee /etc/modprobe.d/aic8800_fdrv.conf > /dev/null' <<'EOF'
# Disable AICWFDBG driver debug logging (default is LOGERROR|LOGINFO).
# Re-enable by setting aicwf_dbg_level to 1/3/7/15/31, or live via
# /sys/module/aic8800_fdrv/parameters/aicwf_dbg_level.
options aic8800_fdrv aicwf_dbg_level=0
EOF
```

---

## 1. Install the display script

```sh
ssh <board> 'sudo tee /usr/local/bin/btop-display.sh > /dev/null' <<'EOF'
#!/bin/bash
# Load a Unicode font on tty1 (required for btop box-drawing characters)
/usr/bin/setfont /usr/share/consolefonts/Uni2-TerminusBold18x10.psf.gz -C /dev/tty1
# Switch console to UTF-8 mode (ESC % G)
printf '\033%%G' > /dev/tty1
# Disable screen blanking and hide cursor
/usr/bin/setterm --blank 0 --powersave off --cursor off > /dev/tty1 2>/dev/null || true
# Clear the screen
printf '\033[2J\033[H' > /dev/tty1
export TERM=linux
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
exec /usr/bin/btop
EOF
ssh <board> 'sudo chmod +x /usr/local/bin/btop-display.sh'
```

The font (`Uni2-TerminusBold18x10.psf.gz`) is stock — it ships with the
`console-setup-linux` package already present on the base image, no extra
install needed. It's a bold, larger Terminus variant than the console
default; the `setfont` call is only there to make sure it's active on tty1
specifically (the framebuffer console font can differ per-VT) and that box-
drawing glyphs render instead of `?` boxes.

---

## 2. Install the systemd unit

```sh
ssh <board> 'sudo tee /etc/systemd/system/btop-display.service > /dev/null' <<'EOF'
[Unit]
Description=btop System Monitor Display
Documentation=https://github.com/aristocratos/btop
After=multi-user.target
Before=getty@tty1.service
Conflicts=getty@tty1.service

[Service]
Type=simple
# Switch to tty1 and put keyboard in scancode mode (raw scancodes btop cannot interpret = keyboard disabled)
ExecStartPre=-/usr/bin/chvt 1
ExecStartPre=-/usr/bin/kbd_mode -s -C /dev/tty1
ExecStart=/usr/local/bin/btop-display.sh
# Restore ASCII keyboard mode when service stops
ExecStopPost=-/usr/bin/kbd_mode -a -C /dev/tty1
StandardInput=tty
StandardOutput=tty
StandardError=journal
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=no
User=root
Restart=always
RestartSec=2
KillMode=process

[Install]
WantedBy=multi-user.target
EOF
```

Key points:
- `Conflicts=getty@tty1.service` — systemd stops `getty@tty1` automatically
  when this unit starts (no manual disable of the getty needed; the
  `Conflicts=` relationship is bidirectional). `Conflicts=` alone does **not**
  imply ordering, though — the `Before=getty@tty1.service` line above is what
  makes the takeover deterministic on boot instead of racing with the getty
  generator (harmless in practice on `lpi3h-f1a0` today since it was applied
  by hand after boot, but worth having if this ships in `overlay/` and runs
  from the very first boot of every image).
- `kbd_mode -s` puts the console keyboard driver in raw scancode mode, which
  btop can't interpret as input — this is a deliberate way to disable local
  keyboard interaction on tty1 while the monitor runs, not a bug. The
  `ExecStopPost` restores normal (`-a`, ASCII) mode if the service ever
  stops, so a later interactive login on tty1 still works.
- `Restart=always` means killing btop just respawns the whole service
  (font reload, chvt, etc.) rather than leaving a login prompt behind.

---

## 3. Enable and start

```sh
ssh <board> 'sudo systemctl daemon-reload && sudo systemctl enable --now btop-display.service'
```

Verify:

```sh
ssh <board> 'systemctl status btop-display.service getty@tty1.service --no-pager'
# btop-display.service: active (running)
# getty@tty1.service:   inactive (stopped by Conflicts=)
```

Physically check the HDMI/local display — tty1 should now show btop
full-screen instead of a login prompt. SSH access is unaffected (this only
touches the local VT).

---

## 4. To revert

```sh
ssh <board> '
sudo systemctl disable --now btop-display.service
sudo systemctl restart getty@tty1.service
'
```

---

## Caveat: local login on tty1 is gone

With `btop-display.service` running, tty1 (HDMI + attached keyboard) no
longer offers a login prompt at all — `getty@tty1` is stopped for as long as
btop owns the console. If network/SSH access ever fails on a board running
this by default, HDMI+keyboard is **not** a fallback anymore.

The serial console is unaffected — `serial-getty@ttyS0.service` is a
separate unit that this setup doesn't touch, so `/dev/ttyUSB0` at 115200
baud still gets a normal login prompt regardless of tty1's state (see
`## Serial console interaction` in `CLAUDE.md`). So recovery without
network is still possible via serial, or by pulling the SD card — just not
via a monitor plugged directly into the board.

This is the main tradeoff to weigh before adding this to `overlay/` so it
ships on every image by default, versus keeping it as a per-board opt-in via
this runbook.

---

## Making this the default for new images

If this should ship on every board rather than being a one-off, add it to
`overlay/`:

- `overlay/usr/local/bin/btop-display.sh`
- `overlay/etc/systemd/system/btop-display.service`
- a symlink under `overlay/etc/systemd/system/multi-user.target.wants/` →
  `../btop-display.service` (mirrors how `firstboot.service` is enabled —
  see `overlay/etc/systemd/system/multi-user.target.wants/`)

`btop` is already pulled in by `mkrootfs.sh`, so no package-list change is
needed. Rebuild the overlay with `bash mkoverlay.sh` and reflash/redeploy to
test — see `CLAUDE.md` build flow.
