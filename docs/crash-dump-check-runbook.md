# Crash Dump Check Runbook — LonganPi 3H

## Context

As of kernel `6.18.48-14` (2026-09-02), `lpi3h-f1a0` has:

- **pstore/ramoops**: 512 KiB reserved at `0x40040000` (right after the BL31
  secmon region), registered as the `pstore` backend, mounted at
  `/sys/fs/pstore`. Continuously logs console output plus any panic/oops
  kmsg dump.
- **Panic escalation**: `kernel.panic_on_oops=1`, `kernel.panic=10` (auto
  warm-reboot 10s after any panic), `kernel.softlockup_panic=1`,
  `kernel.hardlockup_panic=1`, `kernel.hung_task_panic=1` (120s timeout) —
  a hang or oops now escalates into a panic instead of sitting frozen
  forever.
- **Hardware watchdog backstop**: `systemd` pets `/dev/watchdog0` every 15s
  (`RuntimeWatchdogSec=30` in `overlay/etc/systemd/system.conf.d/watchdog.conf`).
  If PID 1 itself stops running (fully wedged kernel, interrupts off),
  hardware resets in 30s with no software involvement.

**Important limitation**: all of the above only survives a *warm* reset
(panic auto-reboot, watchdog reset, `reboot` command). DRAM loses power and
refresh on a full **power cycle** (pulling the plug), which wipes the
ramoops region along with everything else. If the board is unresponsive and
you have to cut power, don't expect anything in pstore afterward — this is
a physics limitation, not a config gap.

Config source:
- Kernel: `CONFIG_PSTORE`, `CONFIG_PSTORE_RAM`, `CONFIG_PSTORE_CONSOLE`,
  `CONFIG_PSTORE_PMSG`, `CONFIG_PANIC_ON_OOPS`, `CONFIG_PANIC_TIMEOUT=10`,
  `CONFIG_SOFTLOCKUP_DETECTOR`, `CONFIG_BOOTPARAM_SOFTLOCKUP_PANIC`,
  `CONFIG_HARDLOCKUP_DETECTOR`, `CONFIG_BOOTPARAM_HARDLOCKUP_PANIC`,
  `CONFIG_DETECT_HUNG_TASK`, `CONFIG_BOOTPARAM_HUNG_TASK_PANIC` in
  `build/linux/arch/arm64/configs/longanpi_3h_defconfig`.
- DT node: `ramoops@40040000` in
  `build/linux/arch/arm64/boot/dts/allwinner/sun50i-h618-longanpi-3h.dts`.
- Watchdog: `overlay/etc/systemd/system.conf.d/watchdog.conf`.

---

## 1. Confirm whether it actually restarted

```sh
ssh lpi3h-f1a0 'uptime; last reboot | head -5'
```

Compare the boot time against when you last touched the board. A short
uptime alone isn't proof of a crash — you may just be looking at a boot
from routine maintenance (kernel update, manual `reboot`, etc.).

## 2. Check for a captured crash record

```sh
ssh lpi3h-f1a0 'sudo ls -la /sys/fs/pstore/'
```

- **Empty** → either nothing crashed (clean reboot), or it was a hard
  power cycle that wiped DRAM before pstore could be read back.
- **Files present** (`dmesg-ramoops-N`, `console-ramoops-0`,
  `pmsg-ramoops-0`) → a crash was captured. Read the oops/panic record
  first:

```sh
ssh lpi3h-f1a0 'sudo cat /sys/fs/pstore/dmesg-ramoops-0'
```

That file has the panic/oops message and stack trace. `console-ramoops-0`
has the raw console scrollback leading up to the crash (useful when the
crash itself didn't print a clean oops — e.g. a lockup detector firing).

**Pstore records are consumed on read-back** — the kernel clears them from
the persistent region once they're surfaced to the filesystem at boot, so
copy anything you need out before the next reboot discards it.

## 3. If pstore is empty but the board did restart unexpectedly

Check the *previous* boot's systemd journal — it may have flushed to disk
before the reset even if pstore didn't catch anything (e.g. a clean panic
with disk I/O still working before the 10s reboot timer fired):

```sh
ssh lpi3h-f1a0 'sudo journalctl -k -b -1 --no-pager | tail -200'
```

Also check what triggered the reset:

```sh
ssh lpi3h-f1a0 'sudo journalctl -b -1 --no-pager | grep -iE "watchdog|panic|reboot|shutdown"'
```

## 4. No record anywhere

This means either:
- Power was physically cut (DRAM lost refresh, ramoops gone) — nothing
  more can be recovered after the fact. Next time, prefer `sudo reboot`
  over pulling power if the board is at all responsive, or wait the ~30s
  for the hardware watchdog to reset it on its own.
- The freeze was silent enough that neither a lockup detector nor the
  watchdog caught it before you intervened (unlikely now that both are
  armed, but not impossible for very early boot hangs before `systemd`
  starts petting `/dev/watchdog0`).

If you get a live stack dump on the HDMI/serial console again and the board
hasn't reset on its own within ~30-40s, that's worth capturing by hand
(photo, or a laptop logging `/dev/ttyUSB0`) before deciding whether to wait
it out or power-cycle — see [tty1-btop-display-runbook.md](tty1-btop-display-runbook.md)
for serial console setup if needed.
