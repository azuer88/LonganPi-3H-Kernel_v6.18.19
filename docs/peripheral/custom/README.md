# Custom peripherals

Documentation for custom hardware add-ons to the LonganPi 3H that aren't
part of the stock board (`overlay/`, `bsp/`) — one subject per file/set.

## Fan PWM control (AO3400 low-side switch)

- [`fan-pwm-mosfet.md`](fan-pwm-mosfet.md) — circuit doc: BOM, topology,
  PWM frequency/duty recommendations, decoupling, power-on behavior.
- [`schematic1.png`](schematic1.png) — KiCad schematic export.
- [`bom.csv`](bom.csv) / [`cpl.csv`](cpl.csv) — JLCPCB-matched BOM and
  pick-and-place export for the assembled board.
- [`fan_control_userspace.py`](fan_control_userspace.py) — Stage 1:
  temp-controlled fan test script driven from userspace via the sysfs PWM
  interface. Validated `MIN_SPIN_DUTY` and the temp->duty curve against
  the real fan, see comments in the script.
- [`fan_control_kernel_sketch.c`](fan_control_kernel_sketch.c) — Stage 2:
  kernel driver sketch; superseded in practice by the stock `pwm-fan`
  binding (`fan0` in `sun50i-h618-longanpi-3h.dts`), which needed no
  custom driver.

**Status:** built and deployed. Circuit wired to header pin 7 (PH2, PWM
channel 2), driven by the kernel's stock `fan0`/`pwm-fan` cooling device.
Validated end-to-end with a logic analyzer and real CPU stress testing:
cooling-levels tightened, `cpu_critical` lowered to 90C (no cpufreq
throttling exists on this board, so the fan is the sole thermal defense),
and `polling-delay-passive` tuned to 175ms for faster governor response
(`kernel_patches/0070`-`0072`). Cold-start minimum duty measured at 45%
(see `MIN_SPIN_DUTY` in `fan_control_userspace.py`) — notably higher
than the 30% that merely sustains an already-spinning fan.
Header pin 33 (PH3, the SoC dtsi's default PWM1 pin) does NOT work —
see the main README's 40-pin header table.
