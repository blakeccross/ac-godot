class_name MLib
extends RefCounted

## Transcriptions of the `m_lib.c` easing helpers that more than one system needs. Angles are
## radians here rather than the original's s16 (0x10000 to a turn), so callers convert their
## step limits once where they declare them.


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
