class_name MLib
extends RefCounted

## Transcriptions of the `m_lib.c` easing helpers that more than one system needs. Angles are
## radians here rather than the original's s16 (0x10000 to a turn), so callers convert their
## step limits once where they declare them (`2500.0 * MLib.S16`).

## Radians per s16 angle unit (`0x10000` = a full turn).
const S16 := TAU / 65536.0
## `1.0f - sqrtf(0.5f)`: the stock `add_calc` fraction — half the gap every two ticks.
const HALF_FRACTION := 1.0 - sqrt(0.5)


static func s16_to_rad(value: float) -> float:
	return value * S16


## Nearest s16 angle, wrapped to 0..0xFFFF.
static func rad_to_s16(radians: float) -> int:
	return int(round(radians / S16)) & 0xFFFF


## Reinterpret the low 16 bits as a signed `s16` (−0x8000..0x7FFF).
static func s16_signed(value: int) -> int:
	var v: int = value & 0xFFFF
	return v - 0x10000 if v >= 0x8000 else v


## `add_calc_short_angle2`: move a fraction of the shortest way to `target`, clamped to
## `max_step`. Once that fraction rounds away to nothing the original steps by exactly
## `min_step` instead, so a turn cannot stall short of where it is going; with `min_step == 0`
## it stops there instead. Snaps to the target rather than overshooting it.
static func short_angle2(
	value: float, target: float, fraction: float, max_step: float, min_step: float = 0.0
) -> float:
	var diff: float = wrapf(target - value, -PI, PI)
	var step: float = diff * fraction
	if absf(step) > min_step and not is_zero_approx(step):
		step = clampf(step, -max_step, max_step)
	elif is_zero_approx(min_step):
		## `(s16)(diff * fraction)` has truncated to zero and there is no floor to fall back
		## on, so the original stops moving here rather than creeping by fractions.
		return target
	else:
		## The `minStep` branch ignores `max_step`, and takes its sign from the difference
		## rather than from the step that rounded away.
		step = min_step if diff >= 0.0 else -min_step
	if absf(step) >= absf(diff):
		return target
	return value + step


## `add_calc_short_angle3`: always turns the *positive* way — the target is lifted a full
## turn above the value when it sits below it — by `fraction` of that gap, clamped to
## [`min_step`, `max_step`], never past the target. (Dash skids spin one direction only.)
static func short_angle3(
	value: float, target: float, fraction: float, max_step: float, min_step: float
) -> float:
	var gap: float = fposmod(target - value, TAU)
	if is_zero_approx(gap) or is_equal_approx(gap, TAU):
		return target
	var step: float = clampf(gap * fraction, min_step, max_step)
	if step >= gap:
		return target
	return wrapf(value + step, -PI, PI)

