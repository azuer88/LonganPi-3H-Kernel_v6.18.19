#!/usr/bin/env python3
"""Userspace temp-controlled PWM fan test for the AO3400 low-side fan
circuit (see fan-pwm-mosfet.md in this folder).

SKETCH / STARTING POINT — not yet run against real hardware. Fill in
PWM_CHIP / PWM_CHANNEL for the actual pwm-sunxi-enhance channel wired to
H2 pin2 (gate, via R1) before using.

Reads CPU temp the same way docs/scripts/cpu_temp_monitor.py does (via
`sensors -j`, cpu_thermal), maps it to a fan duty cycle, and drives the
fan through the kernel's sysfs PWM interface. Intended as the proof step
before writing a kernel driver: once the curve/behavior here is validated
against the physical fan, port the same logic into a thermal/hwmon
kernel driver (see fan_control_kernel_sketch.c).

Usage:
    sudo ./fan_control_userspace.py
    sudo ./fan_control_userspace.py --dry-run   # print decisions, no sysfs writes
"""
import argparse
import json
import subprocess
import sys
import time

# --- Fill in for the actual board wiring -----------------------------------
# PWM_CHIP/PWM_CHANNEL are NOT GPIO line numbers -- they're the
# pwm-sunxi-enhance controller's own chip/channel indices under
# /sys/class/pwm/, separate from the gpiochip1 numbering in the main
# README's 40-pin header table. Confirm PWM_CHIP against `ls
# /sys/class/pwm/` on the actual board (likely pwmchip0, since
# pwm-sunxi-enhance registers one pwmchip with 6 channels -- see
# build/linux/arch/arm64/boot/dts/allwinner/sun50i-h616.dtsi around the
# `pwm@300a000` node, pwm-number = <6>).
#
# Channel 2 = PH2 = header pin 7 ("PWM2 (pwm-fan)" in the main README) is
# ALREADY claimed by the stock `fan0: pwm-fan` node in
# sun50i-h618-longanpi-3h.dts:97 (status="okay", bound into the thermal
# zone's cooling-maps). Exporting channel 2 from userspace here will fail
# with EBUSY while that node is enabled.
#
# Channel 1 was originally PH3 / header pin 33 ("PWM1"), but that pin does
# NOT output full-swing logic (~0.9-1.2V high instead of 3.3V, confirmed
# via logic analyzer on two separate boards -- see the README's 40-pin
# header table and kernel_patches/0070). kernel_patches/0070 repoints
# pwm1's devicetree pinctrl binding to PG19 / header pin 32 instead (same
# sysfs chip/channel numbers below -- only the physical pin changed).
# PG19 confirmed electrically healthy and validated end-to-end against
# the real fan circuit (see CURVE notes below).
PWM_CHIP = 0
PWM_CHANNEL = 1        # pwm1 -- routed to PG19 / header pin 32 by kernel_patches/0070
PWM_PERIOD_NS = 40000  # 25kHz, see "PWM frequency and duty range" in fan-pwm-mosfet.md
# -----------------------------------------------------------------------------

# Temp (C) -> duty cycle (%) control points, aligned to the kernel's
# existing trip points so results are directly comparable before deciding
# whether to keep them or retune (sun50i-h616.dtsi:1343-1363, fan0 node
# in sun50i-h618-longanpi-3h.dts:97):
#
#   cpu_threshold trip = 60C, hysteresis 0  -> cooling-device states 0..2
#   cpu_target    trip = 70C, hysteresis 0  -> cooling-device states 2..4
#   cooling-levels = <1 100 150 200 255>    -> states 0..4 as %: ~0,39,59,78,100
#
# The kernel's step_wise governor ramps the state up/down by one step per
# polling interval while temp stays above/below a trip -- it does NOT use
# a fixed temp->duty table, so this is an approximation.
#
# EMPIRICAL DATA (2026-09-19, real fan+circuit on lpi3h-f1a0, prototype
# wiring on channel 1 / PG19 / header pin 32 -- see PWM_CHANNEL note
# above; not yet re-validated on the production channel 2 / PH2 / pin 7
# binding that fan0 actually uses):
#
#   Idle (no CPU load), steady-state cpu-thermal temp per duty:
#     30% -> ~49.5C   50% -> ~47.3-47.9C   55% -> ~45.5-46.5C
#     65% -> ~44.5-45.7C   80% -> ~44.2-44.5C
#
#   Under stress-ng --cpu 4 --cpu-load 50 (~50% CPU usage), steady-state:
#     30% -> peaks ~69.7C (too close to 70C, NOT safe)
#     40% -> peaks ~69.4C (still too close, barely better than 30% --
#            airflow response is nonlinear near the fan's stall region)
#     50% -> 61-67C (safe, ~3-8C margin below 70C)
#     55% -> 54-60C
#
# Below 60C we use state0 (~0%, treated as fully off -- 0.4% duty won't
# spin a directly power-switched fan anyway; MIN_SPIN_DUTY overrides this
# once measured). 60-70C we hold at 50% -- empirically the minimum duty
# that keeps real CPU load under 70C with real margin (40% measured too
# close to the limit to trust). >=70C jumps to 100% as a safety ceiling.
# NOT YET TESTED: 100% CPU load (worst realistic case), duties between
# 40-50% and 55-80% under load, or any of this on the production pin 7
# wiring -- retest before treating these as final before kernel handoff.
CURVE = [
    # (temp_c, duty_pct)
    (60, 50),   # cpu_threshold -- was 59 (untested placeholder), now the
                # empirically-validated minimum safe duty under real load
    (70, 100),  # cpu_target:    cooling-levels[4] = 255/255
]

# Minimum duty the fan actually spins at reliably, from testing with
# `--find-min-duty` (see that mode below). The fan is kept running at
# this floor at all times below the first curve point rather than
# switched fully off -- a directly power-switched 2-wire fan (no
# dedicated PWM control pin) is more prone to failing to start from a
# dead stop than to running continuously at a low, known-good duty, and
# avoids repeated stop/restart cycling.
#
# VALIDATED (2026-09-19): manual cold-start bisection on the real fan,
# production wiring (pin 7 / PH2 / channel 2 -- pwm-fan driver
# temporarily unbound via /sys/bus/platform/drivers/pwm-fan/unbind to
# free the channel for raw sysfs control, then rebound afterward).
# 30% only SUSTAINS spinning once already running (confirmed earlier by
# dropping from a 100% kick) -- it does NOT cold-start from a dead stop
# (confirmed fails). True cold-start bisection: 38% no, 42% no, 44% no,
# 45% yes (confirmed 3/3 trials from a fresh dead stop). Static friction
# requires meaningfully more duty than sustaining rotation -- don't
# assume a sustain-only test gives the cold-start floor.
# MIN_SPIN_DUTY = 45 + ~3 points margin. This already sits comfortably
# below the tightened cooling-levels state1 (50%, see fan0 in
# sun50i-h618-longanpi-3h.dts / kernel_patches/0071), so no further DTS
# change was needed for consistency.
MIN_SPIN_DUTY = 48

STARTUP_KICK_DUTY = 100
STARTUP_KICK_SECONDS = 0.75
POLL_INTERVAL_SECONDS = 2.0
HYSTERESIS_C = 0.0  # matches kernel's hysteresis = <0> on both trips


class PwmFan:
    def __init__(self, chip, channel, period_ns, dry_run=False):
        self.chip_path = f"/sys/class/pwm/pwmchip{chip}"
        self.pwm_path = f"{self.chip_path}/pwm{channel}"
        self.channel = channel
        self.period_ns = period_ns
        self.dry_run = dry_run
        self.current_duty_pct = None

    def _write(self, path, value):
        if self.dry_run:
            print(f"  [dry-run] echo {value} > {path}")
            return
        with open(path, "w") as f:
            f.write(str(value))

    def export(self):
        import os
        if not os.path.exists(self.pwm_path):
            self._write(f"{self.chip_path}/export", self.channel)
            time.sleep(0.1)
        self._write(f"{self.pwm_path}/period", self.period_ns)
        self._write(f"{self.pwm_path}/duty_cycle", 0)
        self._write(f"{self.pwm_path}/enable", 1)

    def set_duty_pct(self, pct):
        pct = max(0, min(100, pct))
        duty_ns = int(self.period_ns * pct / 100)
        self._write(f"{self.pwm_path}/duty_cycle", duty_ns)
        self.current_duty_pct = pct

    def kick_start(self):
        """Brief full-duty pulse to overcome static friction from a stop.
        See "Duty cycle" section in fan-pwm-mosfet.md."""
        print(f"Startup kick: {STARTUP_KICK_DUTY}% for {STARTUP_KICK_SECONDS}s")
        self.set_duty_pct(STARTUP_KICK_DUTY)
        time.sleep(STARTUP_KICK_SECONDS)


def read_cpu_temp():
    out = subprocess.run(["sensors", "-j"], capture_output=True, text=True, check=True)
    data = json.loads(out.stdout)
    for chip, features in data.items():
        if "cpu_thermal" not in chip.lower():
            continue
        for label, sub in features.items():
            if not isinstance(sub, dict):
                continue
            for key, value in sub.items():
                if key.endswith("_input"):
                    return value
    raise RuntimeError("cpu_thermal sensor not found via `sensors -j`")


def duty_for_temp(temp_c, last_duty_pct):
    """Walk the curve; apply hysteresis so it doesn't chatter at a
    boundary point. Never returns below MIN_SPIN_DUTY once that's been
    measured and set -- see its definition above."""
    target = 0
    for trip_c, duty_pct in CURVE:
        if temp_c >= trip_c:
            target = duty_pct
    if last_duty_pct is not None and target < last_duty_pct:
        # only step down once we've cooled a bit past the trip point
        for trip_c, duty_pct in CURVE:
            if last_duty_pct > duty_pct and temp_c >= trip_c - HYSTERESIS_C:
                target = max(target, duty_pct)
    return max(target, MIN_SPIN_DUTY)


def find_min_duty(fan, start_pct=10, step_pct=2, settle_seconds=2.5):
    """Interactive sweep to find the lowest duty the fan reliably spins
    at from a dead stop. Run this once per fan model, then hardcode the
    result (plus a couple percent of margin) into MIN_SPIN_DUTY above.

    Ramps up from `start_pct`, pausing at each step for the operator to
    look/listen and confirm. Confirm 2-3 times in a row before trusting a
    value -- fans can start marginally at a duty that then stalls if
    nudged (vibration, dust, orientation)."""
    pct = start_pct
    print("Watching/listening to the fan -- it starts fully stopped.")
    print("At each step: press Enter if NOT spinning, or type 'y' once it "
          "spins reliably (confirm at least twice before trusting it).\n")
    while pct <= 100:
        fan.set_duty_pct(pct)
        print(f"duty = {pct}% ", end="")
        time.sleep(settle_seconds)
        answer = input("spinning? [y/N] ").strip().lower()
        if answer == "y":
            print(f"\nCandidate minimum: {pct}%. Re-run from a stop a "
                  f"couple more times to confirm before setting "
                  f"MIN_SPIN_DUTY = {pct} (consider adding a couple "
                  f"percent margin).")
            fan.set_duty_pct(0)
            return pct
        pct += step_pct
    print("\nNever spun up to 100%. Check wiring/circuit before continuing.")
    fan.set_duty_pct(0)
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true",
                         help="Print decisions without touching sysfs")
    parser.add_argument("--find-min-duty", action="store_true",
                         help="Interactive sweep to find the fan's minimum "
                              "reliable spin-up duty, then exit. Run this "
                              "once per fan model before relying on "
                              "MIN_SPIN_DUTY.")
    args = parser.parse_args()

    fan = PwmFan(PWM_CHIP, PWM_CHANNEL, PWM_PERIOD_NS, dry_run=args.dry_run)
    fan.export()

    if args.find_min_duty:
        find_min_duty(fan)
        return

    try:
        # One-time cold-start kick: MIN_SPIN_DUTY alone may not overcome
        # static friction from a dead stop even if it sustains rotation
        # once spinning (common for these fans -- see "Duty cycle" notes
        # in fan-pwm-mosfet.md). After this, the fan is kept running
        # continuously at >=MIN_SPIN_DUTY (duty_for_temp() never returns
        # below it), so this kick only ever fires once at script start,
        # not on every temp-driven transition. Continuous low-speed
        # operation also means the fan doubles as a visual/audible
        # "board is powered and running" indicator rather than only
        # spinning up once things are already hot.
        if MIN_SPIN_DUTY > 0:
            fan.kick_start()
            fan.set_duty_pct(MIN_SPIN_DUTY)

        while True:
            temp_c = read_cpu_temp()
            target_duty = duty_for_temp(temp_c, fan.current_duty_pct)

            if target_duty != fan.current_duty_pct:
                fan.set_duty_pct(target_duty)

            print(f"{temp_c:5.1f}C -> duty {fan.current_duty_pct:3d}%")
            time.sleep(POLL_INTERVAL_SECONDS)
    except KeyboardInterrupt:
        print("\nStopping, fan set to 0%")
        fan.set_duty_pct(0)
        sys.exit(0)


if __name__ == "__main__":
    main()
