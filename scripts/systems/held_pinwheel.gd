class_name HeldPinwheel
extends RefCounted

## The pinwheel in hand (`m_player_item_windmill`). Its `wait` clip turns the blades; how fast
## it plays is the speed `Player_actor_Item_windmill_CulcRotationSpeed` eases toward.


## Carried through the air at `gx_per_frame`, in wind of `wind_power`.
static func target_speed(gx_per_frame: float, wind_power: float) -> float:
	return 8.0 * gx_per_frame + 10.0 * wind_power


## `add_calc(&speed, target, 1 − √(1 − frac), max / 2, min / 2)` over `frames` frames.
static func ease_speed(speed: float, target: float, frames: float) -> float:
	var frac: float = absf(0.005 * target) + 0.02
	var max_step: float = (absf(0.03 * target) + 0.3) * 0.5
	var min_step: float = (absf(0.005 * target) + 0.1) * 0.5
	var step: float = (target - speed) * (1.0 - sqrt(1.0 - minf(frac, 1.0)))
	step = clampf(step, -max_step, max_step)
	if absf(step) < min_step:
		step = clampf(target - speed, -min_step, min_step)
	var next: float = speed + step * frames
	## Never past the target when several frames pass at once.
	return minf(next, target) if step > 0.0 else maxf(next, target)
