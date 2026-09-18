# PWM Fan Control via Low-Side N-Channel MOSFET

Low-side MOSFET switch for PWM-controlled fan speed on the LonganPi 3H, using
the board's PWM output (`pwm-sunxi-enhance`, see `kernel_patches/0064`,
`0065`) to drive a 2-wire fan that has no onboard PWM control pin.

Schematic: [`schematic1.png`](schematic1.png)

## Why a MOSFET instead of a driver IC

A DRV8833 (dual H-bridge) also works for this, but a fan never needs
direction reversal, so a single low-side MOSFET switch is simpler and cheaper
than dedicating an H-bridge channel to it. Use a 4-wire PWM fan directly
(its dedicated PWM pin) if available — this circuit is only needed for
2-wire fans.

## Target fan

**3507 blower** (35×35×7mm centrifugal/blower fan, not axial), 5V,
rated **0.15A** (150mA). All component margins below (Q1 current
rating, D1 current rating, C2 rail-sag buffering) are checked against this
load — comfortable headroom throughout, nothing upsized for it.

Being a blower rather than an axial fan likely explains the pronounced
stall region observed during testing — centrifugal impellers generally
have a steeper torque/RPM dropoff near their minimum than axial fans, and
this is consistent with the sizeable gap measured between sustaining
rotation (30%) and reliably cold-starting from a dead stop (45%); see
`fan_control_userspace.py`'s `MIN_SPIN_DUTY` notes.

## Bill of materials

| Ref | Part | Notes |
|-----|------|-------|
| Q1 | AO3400 | Logic-level N-channel MOSFET (SOT-23). Rds(on) spec'd down at Vgs≈2.5V, a closer match to the 3.3V GPIO drive than the originally-considered IRLZ44N (TO-220, rated for Vgs=5V). Rated ~5.7A continuous — vast headroom over the 0.15A fan load. |
| R1 | 220Ω | Gate series resistor — limits inrush current charging gate capacitance, protects the GPIO pin. |
| R2 | 10KΩ | Gate pulldown — holds gate at 0V (MOSFET off) whenever the GPIO is floating/tri-stated (e.g. during boot, before the PWM driver initializes). |
| D1 | 1N5819 | Schottky flyback diode across the fan, cathode to +5V, anode to the switched drain node. Clamps inductive kickback from the fan's motor coils when the MOSFET turns off. |
| H2 | PZ254V-11-03P (3-pin) | Input header from SBC: pin1 = +5V, pin2 = PWM signal (through R1 to gate), pin3 = GND. |
| H1 | PZ254V-11-02P (2-pin) | Fan connector, wired between +5V and the switched drain node. |
| C1 *(optional)* | 47µF electrolytic | Bulk cap on the +5V rail near H2 (input header) — buffers pulsed current draw, prevents rail sag/noise into shared +5V. Schematic doesn't call out a voltage rating; use 16V for ~3x margin over the 5V rail (avoid tantalum — fails short under transient stress; standard aluminum electrolytic or X5R/X7R ceramic preferred). |
| C2 *(optional)* | 1µF ceramic | Decoupling, directly across H1 (fan pins) — suppresses switching-edge EMI local to the fan. |

Power dissipation check (both resistors, worst case with gate driven high):
gate draws no continuous DC current (capacitive input), so current flows
GPIO → R1 → R2 → GND. At 3.3V logic: I ≈ 3.3V / 10.22kΩ ≈ 320µA →
R2 ≈ 1mW, R1 ≈ 0.02mW. Standard 100mW (1/8W or 1/10W) resistors have
~100x margin here.

## Topology

```
+5V ──────┬────────────────┬───────────────────┐
          │                │                   │
   [C1 47µF,           [FAN +]              (D1 1N5819,
    optional]              │                cathode up)
          │             [FAN -] ──[C2 1µF, optional]
         GND               ├───────────────────┘
                            │
                       Q1 Drain
                            │
GPIO(PWM) ──[R1 220Ω]──●── Q1 Gate
                            │
                       [R2 10KΩ to GND]
                            │
                       Q1 Source
                            │
                           GND
```

MOSFET does low-side switching: current flows +5V → fan → drain (switched)
→ source → GND. Fan power comes from the +5V rail, not from the GPIO.

**Grounding:** the pulldown, MOSFET source, and header GND must all share a
common ground with the fan's power supply — if the fan runs off a separate
supply, tie its ground back to the board GND or switching will not behave
correctly.

## PWM frequency and duty range

**Frequency: 20–25kHz** (matches the Intel 4-wire fan PWM spec, even though
this circuit chops the 2-wire fan's supply rather than driving a dedicated
PWM control line):
- Above 20kHz keeps switching noise out of the audible range — lower than
  that (especially 100Hz–5kHz) causes audible coil whine/buzz as the
  MOSFET chops the supply.
- No real benefit going much higher (e.g. >50kHz) — gate switching losses
  increase slightly and the fan motor's own inductance can't respond any
  faster anyway.
- Set via the PWM `period` sysfs attribute in ns — 25kHz = 40000ns. Confirm
  the specific `pwm-sunxi-enhance` channel/divider can hit this period.

**Duty cycle: practically ~25–100%, not 0–100%:**
- Unlike a true 4-wire PWM fan (constant supply voltage, only a signal pin
  is chopped, so the fan's internal driver stays powered and can idle at
  low duty), this circuit chops the fan's actual supply. Below roughly
  20–30% duty (varies per fan) there isn't enough average voltage/torque
  to overcome static friction, and the fan stalls, buzzes, or fails to
  start rather than spinning slowly.
- Clamp the control script to a minimum duty floor (e.g. ≥25%) rather than
  allowing arbitrarily low nonzero duty cycles.
- Add a **startup kick**: drive 100% duty for ~0.5–1s on any 0%→on
  transition, then drop to the target duty. Without this, commanding a
  fan straight from standstill to a low-mid duty cycle may not spin it up
  at all.
- Determine the actual reliable minimum empirically per fan model (step
  duty down from 100% and note the stall point), then set the floor with
  margin above it. `fan_control_userspace.py --find-min-duty` automates
  this sweep.
- **Design choice: keep the fan spinning continuously at that measured
  minimum rather than switching it fully off below the first trip
  point.** A directly power-switched 2-wire fan is more prone to failing
  a cold start than to sustaining rotation once already spinning, so
  idling at the floor avoids repeated stop/restart cycling. As a side
  benefit, a fan that's always turning (even slowly) at idle doubles as
  a quick visual/audible cue that the board is powered and running,
  rather than only spinning up once it's already hot.

## Decoupling / supply integrity

Not needed for smoothing the fan's PWM waveform itself — the motor
windings' own inductance already low-pass filters the current, which is
why direct PWM chopping of DC fans works without an output filter. An LC
output filter would just turn PWM speed control into a fixed analog
voltage and isn't recommended here.

What *is* worth adding, for EMI/rail integrity rather than speed control —
marked **Optional** on the schematic since the circuit functions without
them, especially at this fan's low 0.15A draw:

| Component | Placement | Purpose |
|-----------|-----------|---------|
| C2, 1µF ceramic | Directly across H1 (fan pins) | Suppresses high-frequency ringing/EMI from switching edges, local to the fan. |
| C1, 47µF electrolytic | +5V rail near H2 (input header) | Buffers the pulsed current draw from switching the fan's inductive load, prevents rail sag/noise coupling into other board electronics sharing the +5V rail. Use a 16V rated part for ~3x margin over the 5V rail; avoid tantalum (fails short under transient stress). |

A drain-source RC snubber on Q1 is not included — only add one if ringing
is actually observed on a scope; at these currents (<a few hundred mA)
and short wire runs it's unlikely to be needed.

## Behavior at power-on

The fan does **not** turn on by itself. R2 holds the gate at 0V by default,
so Vgs = 0V and the MOSFET is off until the SBC's software explicitly:

1. Configures the GPIO pin as a PWM output (`pwm-sunxi-enhance` / sysfs PWM
   interface).
2. Sets a duty cycle > 0%.

Until that happens (including during kernel boot, before any control script
runs), the fan stays off as long as the pin isn't actively muxed/driven high
by something else in the meantime.

## PWM channel / header pin

H2 pin2 (PWM signal in, through R1 to the gate) should go to a header pin
carrying a real PWM output from `pwm-sunxi-enhance`, not just any GPIO —
see the main [`README.md`](../../../README.md) 40-pin header table.

- **Deployment: header pin 7 (PH2, PWM channel 2).** This pin is already
  the consumer of the stock `fan0: pwm-fan` node in
  `sun50i-h618-longanpi-3h.dts:97`, which is pre-bound into the CPU
  thermal zone's cooling-maps (`cooling-levels = <1 100 150 200 255>`,
  `pwms = <&pwm 2 50000 1>` — 20kHz). Wiring here reuses that binding
  directly — likely no new kernel code needed, see
  `fan_control_kernel_sketch.c`'s devicetree-route note.
- **Stage-1 prototyping: header pin 33 (PH3, PWM channel 1)** instead —
  channel 2 is already claimed by the in-kernel `fan0` node
  (`status = "okay"`), so raw sysfs `export` of it from userspace fails
  with `EBUSY` while that node is enabled. Channel 1 is free, so
  `fan_control_userspace.py` defaults to it to avoid touching the
  devicetree during testing. Move the physical wire to pin 7 once
  validated and ready to hand off to the existing `fan0` node.
- PWM chip/channel numbers are **not** the same namespace as the GPIO
  line numbers in the header table (`gpiochip1`, `port × 32 + pin`) —
  they're separate indices under `/sys/class/pwm/`, defined by
  `pwm-sunxi-enhance`'s own sub-node numbering in
  `sun50i-h616.dtsi` (`pwm@300a000`, `pwm-number = <6>`).

## Implementation sketch

Two-stage plan, code sketches in this folder (both unvalidated):

1. [`fan_control_userspace.py`](fan_control_userspace.py) — userspace
   temp-controlled test script (sysfs PWM interface), validates the duty
   curve, hysteresis, and startup-kick timing against the real fan before
   anything moves into the kernel.
2. [`fan_control_kernel_sketch.c`](fan_control_kernel_sketch.c) — kernel
   driver sketch (thermal cooling device + hwmon), to port the proven
   curve into once (1) is validated. Also documents a devicetree-only
   route via the stock `pwm-fan` binding that may make a custom driver
   unnecessary — try that first.

## Status

Schematic reviewed and confirmed correct (component selection, gate
resistor + pulldown placement, flyback diode orientation, fan wired for
low-side switching, common ground). Reference designators (`H?`, `D?`, `Q?`,
`R?` in the KiCad schematic) still need running through Annotate Schematic
before BOM/PCB export. Not yet built or tested on hardware.
