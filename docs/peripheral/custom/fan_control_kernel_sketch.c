// SPDX-License-Identifier: GPL-2.0
/*
 * SKETCH — kernel driver stage for the AO3400 low-side PWM fan circuit
 * (see fan-pwm-mosfet.md in this folder). Not built or tested.
 *
 * Once fan_control_userspace.py has validated the duty curve, hysteresis,
 * startup-kick timing, and stall floor against the real fan, port those
 * numbers here. This is intentionally close to upstream drivers/hwmon/
 * pwm-fan.c + the thermal cooling-device glue it already provides —
 * for a plain 2-wire fan with no tach line, that stock driver is likely
 * sufficient via devicetree alone (see "Devicetree route" below) and this
 * custom driver may not even be needed. Write this only if the cooling
 * curve/hysteresis behavior needs logic the stock pwm-fan binding can't
 * express (e.g. the startup-kick pulse), since pwm-fan does not support
 * anything like a StepWise kick sequence.
 *
 * Registers as both:
 *   - a thermal cooling device, so it can be bound to a trip point in the
 *     SoC's thermal zone (arch/arm64/boot/dts/allwinner/sun50i-h616*.dts)
 *   - an hwmon device, so `pwmN` / fan state show up under /sys/class/hwmon
 *
 * TODO before use:
 *   - devicetree binding for the PWM + optional startup-kick timing,
 *     compatible = "lpi3h,ao3400-pwm-fan" (or similar) bound to the
 *     pwm-sunxi-enhance controller output feeding H2 pin2 / R1 / Q1 gate.
 *   - confirm min/curve duty values against fan_control_userspace.py
 *     results (MIN_DUTY, CURVE, HYSTERESIS_C in that script).
 *   - confirm whether the startup kick is even necessary once this is a
 *     kernel-resident controller (less chance of userspace-driven jumps
 *     straight from 0% to a mid duty, since the kernel curve/hysteresis
 *     logic controls all transitions instead of ad hoc script calls).
 */

#include <linux/hwmon.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/pwm.h>
#include <linux/thermal.h>

/* Mirrors CURVE / MIN_DUTY / HYSTERESIS_C in fan_control_userspace.py —
 * keep both in sync until the values are proven and this table is final. */
struct fan_curve_point {
	int temp_mc;   /* millidegrees C, to match thermal framework units */
	int duty_pct;
};

static const struct fan_curve_point fan_curve[] = {
	{ 45000, 0 },
	{ 50000, 25 },  /* MIN_DUTY floor -- see fan-pwm-mosfet.md duty range notes */
	{ 60000, 45 },
	{ 70000, 65 },
	{ 80000, 100 },
};

#define FAN_HYSTERESIS_MC	3000
#define FAN_STARTUP_KICK_PCT	100
#define FAN_STARTUP_KICK_MS	750
#define FAN_PWM_PERIOD_NS	40000  /* 25kHz, see fan-pwm-mosfet.md */

struct lpi3h_fan {
	struct device *dev;
	struct pwm_device *pwm;
	struct thermal_cooling_device *cdev;
	struct mutex lock;
	int current_duty_pct;
};

static int duty_for_temp(int temp_mc, int last_duty_pct)
{
	int target = 0;
	int i;

	for (i = 0; i < ARRAY_SIZE(fan_curve); i++) {
		if (temp_mc >= fan_curve[i].temp_mc)
			target = fan_curve[i].duty_pct;
	}

	/* Apply hysteresis on the way down so it doesn't chatter right at
	 * a trip boundary -- same logic as duty_for_temp() in
	 * fan_control_userspace.py. */
	if (target < last_duty_pct) {
		for (i = 0; i < ARRAY_SIZE(fan_curve); i++) {
			if (last_duty_pct > fan_curve[i].duty_pct &&
			    temp_mc >= fan_curve[i].temp_mc - FAN_HYSTERESIS_MC)
				target = max(target, fan_curve[i].duty_pct);
		}
	}
	return target;
}

static int lpi3h_fan_set_duty(struct lpi3h_fan *fan, int duty_pct)
{
	struct pwm_state state;
	int ret;

	pwm_get_state(fan->pwm, &state);
	state.period = FAN_PWM_PERIOD_NS;
	state.duty_cycle = div_u64((u64)FAN_PWM_PERIOD_NS * duty_pct, 100);
	state.enabled = duty_pct > 0;

	ret = pwm_apply_state(fan->pwm, &state);
	if (ret)
		return ret;

	fan->current_duty_pct = duty_pct;
	return 0;
}

static int lpi3h_fan_set_target(struct lpi3h_fan *fan, int temp_mc)
{
	int target, ret;

	mutex_lock(&fan->lock);

	target = duty_for_temp(temp_mc, fan->current_duty_pct);

	if (fan->current_duty_pct == 0 && target > 0) {
		/* Startup kick -- overcome static friction from a stop.
		 * TODO: confirm still needed once curve transitions are
		 * kernel-driven rather than ad hoc userspace writes; the
		 * userspace sketch needed this because it could jump straight
		 * from 0% to a mid duty on first read. */
		dev_dbg(fan->dev, "startup kick %d%% for %dms\n",
			FAN_STARTUP_KICK_PCT, FAN_STARTUP_KICK_MS);
		ret = lpi3h_fan_set_duty(fan, FAN_STARTUP_KICK_PCT);
		if (ret)
			goto out;
		msleep(FAN_STARTUP_KICK_MS);
	}

	if (target != fan->current_duty_pct)
		ret = lpi3h_fan_set_duty(fan, target);
	else
		ret = 0;

out:
	mutex_unlock(&fan->lock);
	return ret;
}

/* --- thermal cooling-device ops --- */

static int lpi3h_fan_get_max_state(struct thermal_cooling_device *cdev,
				    unsigned long *state)
{
	*state = ARRAY_SIZE(fan_curve) - 1;
	return 0;
}

static int lpi3h_fan_get_cur_state(struct thermal_cooling_device *cdev,
				    unsigned long *state)
{
	struct lpi3h_fan *fan = cdev->devdata;
	int i;

	for (i = ARRAY_SIZE(fan_curve) - 1; i >= 0; i--) {
		if (fan->current_duty_pct >= fan_curve[i].duty_pct) {
			*state = i;
			return 0;
		}
	}
	*state = 0;
	return 0;
}

static int lpi3h_fan_set_cur_state(struct thermal_cooling_device *cdev,
				    unsigned long state)
{
	struct lpi3h_fan *fan = cdev->devdata;

	if (state >= ARRAY_SIZE(fan_curve))
		return -EINVAL;

	return lpi3h_fan_set_duty(fan, fan_curve[state].duty_pct);
}

static const struct thermal_cooling_device_ops lpi3h_fan_cooling_ops = {
	.get_max_state = lpi3h_fan_get_max_state,
	.get_cur_state = lpi3h_fan_get_cur_state,
	.set_cur_state = lpi3h_fan_set_cur_state,
};

static int lpi3h_fan_probe(struct platform_device *pdev)
{
	struct lpi3h_fan *fan;

	fan = devm_kzalloc(&pdev->dev, sizeof(*fan), GFP_KERNEL);
	if (!fan)
		return -ENOMEM;

	fan->dev = &pdev->dev;
	mutex_init(&fan->lock);

	fan->pwm = devm_pwm_get(&pdev->dev, NULL);
	if (IS_ERR(fan->pwm))
		return dev_err_probe(&pdev->dev, PTR_ERR(fan->pwm),
				      "failed to get PWM\n");

	fan->cdev = devm_thermal_of_cooling_device_register(
		&pdev->dev, pdev->dev.of_node, "lpi3h-fan", fan,
		&lpi3h_fan_cooling_ops);
	if (IS_ERR(fan->cdev))
		return dev_err_probe(&pdev->dev, PTR_ERR(fan->cdev),
				      "failed to register cooling device\n");

	platform_set_drvdata(pdev, fan);
	dev_info(&pdev->dev, "lpi3h AO3400 PWM fan driver registered\n");
	return 0;
}

static const struct of_device_id lpi3h_fan_of_match[] = {
	{ .compatible = "lpi3h,ao3400-pwm-fan" },
	{ }
};
MODULE_DEVICE_TABLE(of, lpi3h_fan_of_match);

static struct platform_driver lpi3h_fan_driver = {
	.probe = lpi3h_fan_probe,
	.driver = {
		.name = "lpi3h-ao3400-pwm-fan",
		.of_match_table = lpi3h_fan_of_match,
	},
};
module_platform_driver(lpi3h_fan_driver);

MODULE_DESCRIPTION("LonganPi 3H AO3400 low-side PWM fan driver (sketch)");
MODULE_LICENSE("GPL");

/*
 * Devicetree route (likely sufficient — this already exists, use it
 * before writing the driver above):
 *
 * sun50i-h618-longanpi-3h.dts:97 already has a stock `fan0: pwm-fan`
 * node, bound into the CPU thermal zone's cooling-maps, using channel 2
 * (PH2 / header pin 7):
 *
 *   fan0: pwm-fan {
 *       compatible = "pwm-fan";
 *       cooling-levels = <1 100 150 200 255>;
 *       #cooling-cells = <2>;
 *       pwms = <&pwm 2 50000 1>;   // channel 2, 50000ns = 20kHz
 *       status = "okay";
 *   };
 *
 * Wiring H2 pin2 (PWM signal into R1/gate, see fan-pwm-mosfet.md) to
 * header pin 7 reuses this node directly — no new kernel code needed.
 * upstream drivers/hwmon/pwm-fan.c (the driver behind "pwm-fan") has no
 * startup-kick concept, so confirm with fan_control_userspace.py whether
 * the fan reliably starts from the curve's MIN_DUTY floor alone (command
 * MIN_DUTY from a cold stop, no kick, see if it spins up). If so, just
 * retune this node's `cooling-levels` (and the `cpu_threshold` /
 * `cpu_target` trip points it's mapped to) to match the values validated
 * in userspace, rather than writing anything below. Only fall back to
 * the custom driver in this file if the startup-kick sequence proves
 * necessary — pwm-fan has no way to express that.
 */
