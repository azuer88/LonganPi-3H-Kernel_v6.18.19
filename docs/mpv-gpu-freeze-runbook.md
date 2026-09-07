# mpv / Panfrost GPU Freeze Investigation Runbook

## Context

`mpv` (`vo=gpu`, `gpu-context=drm`, `drm-device=/dev/dri/card0`) freezes
non-deterministically on `lpi3h-f1a0` after anywhere from ~15 minutes to
~2 hours of playback. Audio/video stop advancing on screen; the process
stays alive (not crashed, no OOM/panic). Goal is a stable GPU-accelerated
(Panfrost/Mesa) playback path — falling back to `vo=drm` (CPU-based
scaling, no GPU accel) is explicitly **not** an acceptable fix, only a
diagnostic-elimination step.

This mirrors an earlier, less-instrumented hang investigation on
`lpi3h-f182` (see memory `project_mpv_hang_investigation.md` /
`project_mpv_playback.md` if you have access to that project's memory).

## What's currently instrumented on `lpi3h-f1a0`

- **`drm.debug=0x1a`** (CORE|DRIVER|ATOMIC bits) — live via
  `/sys/module/drm/parameters/debug` and persisted in both extlinux.conf
  copies. See `docs/devices/f1a0-board-notes.md` (gitignored — board
  notes aren't checked into the repo) for exactly where.
- **Persistent DRM trace logger** — `dmesg`'s kernel ring buffer only
  holds ~15 seconds of history at this verbosity (confirmed: ~5700
  lines/15s), which is useless for seeing the run-up to a freeze that
  happened minutes ago. Instead, a detached logger streams continuously
  to a file that doesn't wrap:
  ```sh
  sudo sh -c "nohup dmesg -w -T >> /tmp/drm-trace.log 2>&1 < /dev/null &"
  ```
  Grows ~2.8MB/min — truncate it (`sudo truncate -s 0 /tmp/drm-trace.log`)
  after each healthy check to keep it manageable. Check it's alive with
  `pgrep -f "dmesg -w"` and restart if it died.
- **Freeze/health CSV** — `/tmp/mpv-freeze-log.csv` on the board,
  columns: `timestamp,elapsed_min,status,temp_gpu,temp_cpu,temp_ve,
  temp_ddr,loadavg1,mpv_cpu_pct`. Appended on every check (healthy or
  frozen) to build a timing/thermal/load correlation dataset.
- **Continuous temperature log** — `cpu_temp_monitor.py`
  (`docs/scripts/cpu_temp_monitor.py`, deployed to
  `/home/default/cpu_temp_monitor.py`) now supports `--log-file`, run by
  the user directly in their own terminal:
  ```sh
  python3 cpu_temp_monitor.py --log-file /home/default/cpu_temp.csv
  ```
  Independent ground truth, 1Hz samples, `timestamp,temp_c`.
- **gdb 13.1** installed (`apt-get install gdb`) for backtrace capture.

## Check procedure (used by the monitoring loop)

**Healthy check:**
1. `ssh lpi3h-f1a0 'pgrep -a mpv; PID=$(pgrep mpv|head -1); ps -o pid,stat,etime,cmd -p $PID'`
2. Sample CPU%/TIME+ twice a few seconds apart (`top -bn1 -p $PID`) to
   confirm it's actually advancing, not just resident.
3. If healthy: append a CSV row (status=healthy) with current temps
   (`/sys/class/thermal/thermal_zone{0-3}/temp` — 0=gpu-thermal,
   1=ve-thermal, 2=cpu-thermal, 3=ddr-thermal), `loadavg` first field,
   mpv's `%CPU`. Truncate `/tmp/drm-trace.log`.

**Frozen (no CPU/TIME+ progress across samples):**
1. Append the CSV row first (status=frozen) — don't lose the data point.
2. **Do not truncate** `/tmp/drm-trace.log` — grep the *entire*
   accumulated file (it now holds the full pre-freeze run-up, not just
   the last 15s):
   - `grep -iE 'panfrost|reset|stall|mmu' /tmp/drm-trace.log`
   - `grep -i fault /tmp/drm-trace.log | grep -v default_clear` (the
     naive `fault` grep false-positives on
     `drm_atomic_state_**default**_clear` — exclude it explicitly)
   - Eyeball the last ~200 lines before the log goes silent for anything
     besides the routine "committed cleanly, then vblank auto-disabled
     after ~5s idle" pattern (that pattern itself is *normal* DRM
     power-save behavior, not a symptom).
3. `sudo gdb -p <pid> --batch -ex "thread apply all bt"` for a full
   thread dump. Note: the `mpv:disk$0` thread that shows up stuck in
   `pthread_cond_wait` inside `libgallium*.so` (or `sun4i-drm_dri.so` on
   older Mesa) in every single capture so far is very likely Mesa's
   shader disk-cache worker thread (`util_queue` naming convention:
   `<process>:<queue>$<index>`) — it's idle by design almost all the
   time, hang or no hang. **Don't over-weight it as "the" stuck thread**;
   look across all threads instead.
4. Kill and relaunch: `kill -9 <pid>`, then
   `cd /home/default && nohup mpv "Rampage (2018).mp4" >/tmp/mpv.log 2>&1 </dev/null &`.
   Restart the `dmesg -w` logger too (truncate first).
5. Record findings.

## Findings so far

- **Kernel completes commits cleanly.** Every captured freeze shows the
  last `drm_atomic_nonblocking_commit` → `__drm_atomic_state_free`
  succeeding normally, immediately followed by the kernel's routine
  idle vblank auto-disable ~5s later (`sun4i_crtc_disable_vblank`) —
  standard DRM power-save behavior, not a fault. No dropped event, no
  timeout, no error logged at the kernel level in any capture.
- **No Panfrost/GPU driver errors observed** in any capture:
  `panfrost`, `mmu`, `reset`, `stall`, `gpu` all return zero matches in
  `dmesg` around freeze time (checked with the corrected `fault` grep
  that excludes the `default_clear` false positive). **Strengthened
  2026-09-07**: with the persistent `dmesg -w` logger running, one
  freeze was captured with a complete 264,295-line trace covering the
  *entire* ~56-minute pre-freeze run (not just the last 15s the ring
  buffer would otherwise retain) — still zero matches. This is a solid
  negative result, not just "nothing visible in a short window."
- **Mesa upgrade (22.3.6 → 25.0.7-2~bpo12+1 via bookworm-backports)
  did NOT fix it.** Same bug reproduced on the new Mesa, just relocated
  into the new merged `libgallium.so` (Mesa 25 merged all Gallium
  backends into one shared object). Don't re-attempt a version-bump fix
  without new evidence.
- **Not thermal.** Independent `cpu_temp_monitor.py` readings and the
  CSV's thermal-zone samples both stay well under 65°C — nowhere near
  the H618's throttling range (~90-100°C).
- **Caveat on load numbers collected while `drm.debug=0x1a` is active:**
  the debug logging itself adds real CPU overhead (`systemd-journald`
  and the `dmesg -w` logger both parsing the same verbose `/dev/kmsg`
  firehose, ~12% CPU observed from journald alone) that wasn't present
  during the original pre-instrumentation freezes. Don't treat load
  numbers from this period as directly comparable to "normal" playback.

## Likely trigger found: ALSA audio underrun (2026-09-07)

After the kernel side came up clean, we switched to Mesa/EGL-side
logging: `drm.debug` off, `dmesg -w` logger stopped, mpv relaunched
with `EGL_LOG_LEVEL=debug MESA_DEBUG=1 mpv --msg-level=all=v
--log-file=/tmp/mpv-debug.log` (stderr to `/tmp/mpv-egl-stderr.log`).

The very next freeze showed the same final event in both logs,
immediately before all output stops:
```
[ao/alsa] attempt 1 to recover from state 'XRUN'...
[ao/alsa] audio end or underrun
Audio device underrun detected.
[cplayer] restarting audio after underrun
```
gdb showed the audio thread had already returned to normal idle
`pthread_cond_wait` — the underrun recovery itself completed — but the
main thread was stuck in the same `mp_dispatch_queue_process` idle wait
as every prior freeze, and no video frame ever got submitted again.

**Working theory:** something in mpv 0.35.1's own audio-underrun
recovery / AV-resync path (not Mesa, not the kernel) occasionally fails
to re-arm the video dispatch queue afterward — a lost wakeup, not a
crash or error, which is exactly why nothing showed up in any kernel or
Mesa/EGL error log across dozens of captures. This would explain the
board-independence, Mesa-version-independence, and total silence in
every diagnostic layer we've checked so far.

**Note:** `pipewire` and `pulse` audio outputs both fail to initialize
on this rootfs (`can't load config client.conf`) and mpv silently falls
back to `alsa` — worth fixing that config so mpv doesn't hit the
underrun-prone alsa path in the first place, as a natural experiment.

**Confirmed 2026-09-07 with a 2nd occurrence, and refined.** A third
freeze under this instrumentation happened in a run with **three**
ALSA underrun events total — only the last one froze. The first two
each completed their recovery cleanly: `restarting audio after
underrun` immediately followed by `[ao/alsa] starting AO`, then normal
playback resumed. The freezing one stopped dead at `restarting audio
after underrun` — confirmed as the literal last line of
`/tmp/mpv-debug.log` (867 of 867 lines) — **no `starting AO` ever
followed**, unlike the two successful recoveries earlier in the same
run.

**Refined conclusion:** underruns themselves are common and usually
harmless. It's specifically an occasional *failure of the
underrun-recovery's audio device reopen* — the step between logging
"restarting audio after underrun" and "starting AO" — that triggers the
freeze. Very likely a race/lost-wakeup bug in mpv 0.35.1's own ALSA
reinit path, where a failed/stalled reopen leaves something unsignaled
and permanently starves the video dispatch queue, even though the audio
side eventually settles back into an idle (not hung) state. Confidence
is now high: 2/2 freezes match this signature; 2/2 successful
recoveries in the same run did *not* freeze. The diagnostic signature
going forward is "restarting audio after underrun with no following
starting AO," not just "an XRUN happened somewhere nearby."

**Tried and failed: `audio-buffer=1.0`.** Added to
`~/.config/mpv/mpv.conf` on f1a0 (backup: `mpv.conf.bak-20260907`).
Froze again at 20min elapsed after only 1 underrun — same exact
signature (`restarting audio after underrun` as the last line, no
`starting AO`). The buffer size may have reduced underrun *frequency*
somewhat, but doesn't prevent a given underrun-recovery attempt from
failing. **Don't retry other buffer sizes expecting a different
result** — this isn't the right lever.

**Monitoring gotcha found while testing this:** at the check right
before this freeze, the process still showed ~6-7% CPU and TIME+
ticking up fractionally, which looked "healthy" at a glance — but the
video playback timestamp (`KAV:` in the log) had already frozen at that
exact point. A wedged process can still show nonzero CPU from other
threads. **Always cross-check the `KAV:` timestamp in the log, not just
process CPU%/TIME+, before declaring a check healthy.**

**Applied 2026-09-07: installed a real PipeWire server stack.** The
`pipewire`/`pulse` failures weren't a config bug — there was **no
PipeWire or PulseAudio server installed at all** on this rootfs, only
client libraries pulled in as transitive deps. `pulseaudio`/`pipewire`
binaries didn't exist.

Installed: `pipewire pipewire-pulse wireplumber
pipewire-audio-client-libraries` (apt, bookworm main). These are **user**
systemd units, so also ran:
```sh
loginctl enable-linger default
systemctl --user start pipewire pipewire-pulse wireplumber
```
Confirmed `systemctl --user is-enabled` shows all three `enabled` with
`Linger=yes` — persists across reboots without needing an active login
session. RTKit/portal warnings in the logs are cosmetic (no
`xdg-desktop-portal`/polkit for realtime thread priority — doesn't
block audio).

Restarted mpv unchanged (no `--ao` override) — it now picks `AO:
[pipewire]` on the first attempt instead of falling back to `alsa`.
This routes around the buggy `ao_alsa.c` underrun-recovery path
entirely, since it no longer runs.

**CONFIRMED FIXED — 2026-09-07.** Monitored 94 minutes of continuous
playback on the PipeWire backend: zero freezes, zero underruns of any
kind (vs. `alsa` freezing every ~10-65 minutes with underruns every
8-25 minutes). CPU/thermal stayed normal throughout (57-61°C, load
~2-3) — no regression.

**Root cause, final summary:** mpv's `ao_alsa.c` underrun-recovery path
has an intermittent bug where the ALSA device reopen after an XRUN
occasionally fails silently, starving the video dispatch queue and
permanently freezing playback. Specific to the `alsa` output — doesn't
exist on `pipewire`. The root enabler was that this rootfs never had a
real PipeWire/PulseAudio *server* installed (only client libs), so mpv
silently fell back to the buggy `alsa` path on every launch.

**Action item: bake this into the rootfs build.** Add `pipewire
pipewire-pulse wireplumber pipewire-audio-client-libraries` to
`custom/01_install_debs.sh` (or a new `custom/NN_pipewire.sh` script),
and run `loginctl enable-linger <USER_NAME>` during rootfs
customization so the user-session services start without an active
login — this is what made it work on `f1a0`. Without this, every future
SD card image ships with the same silent-fallback-to-alsa bug.

## Open question / what we're still chasing

The kernel side looks clean in every capture — no Panfrost fault, no
dropped completion, no timeout. That points to Mesa/EGL never
*submitting* the next frame's commit, for reasons not yet identified
(the `disk$0` thread that keeps showing up is probably a red herring —
see above). Next real diagnostic options, roughly in order of effort:

1. Keep accumulating CSV data points (timing/thermal/load) across more
   occurrences to check for a pattern before assuming there isn't one.
2. Verbose Mesa/EGL-side logging (`EGL_LOG_LEVEL=debug`, Panfrost's
   `PAN_MESA_DEBUG` env vars) to see what the render/present loop is
   doing right up to the stall, since kernel-side tracing has been
   exhausted without a hit.
3. If a pattern does emerge (e.g. correlates with load spikes, specific
   playback content, or long idle periods before the freeze), use that
   to narrow where in Mesa to instrument next.

`vo=drm` remains a known-working fallback (documented in
`project_mpv_playback` memory) but is explicitly out of scope as a fix
since the goal is a stable GPU-accelerated path.
