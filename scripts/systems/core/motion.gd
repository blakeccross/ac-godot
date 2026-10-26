class_name Motion
extends RefCounted

## Frame-rate independent smoothing and chance, for gameplay that runs on `delta`.
##
## These replace the decomp's per-tick idioms. A tick-stepped `add_calc` gives a different
## curve at every render rate unless it is run through a fixed-tick loop; `damp` gives the
## same curve whether `delta` arrives as one 0.1 s step or ten 0.01 s steps.
##
##     position.x = Motion.damp(position.x, target_x, 0.08, delta)
##     yaw = Motion.damp_angle(yaw, target_yaw, 0.05, delta)
##     if Motion.happens(0.5, delta, _rng):   # about once every two seconds
##         _chirp()
##
## The `*_from_*` helpers are for authoring: they turn a decomp number into the seconds-based
## value once, where the constant is written, with the source cited beside it.


## Moves `current` toward `target`, halving the gap every `half_life` seconds.
static func damp(current: float, target: float, half_life: float, delta: float) -> float:
	return lerpf(current, target, _blend(half_life, delta))


static func damp_vec3(current: Vector3, target: Vector3, half_life: float, delta: float) -> Vector3:
	return current.lerp(target, _blend(half_life, delta))


## `damp` for angles in radians, taking the short way round.
static func damp_angle(current: float, target: float, half_life: float, delta: float) -> float:
	return lerp_angle(current, target, _blend(half_life, delta))


## `damp`, with the speed held between `min_speed` and `max_speed` (units a second): the
## `add_calc(value, target, fraction, max_step, min_step)` shape. It never overshoots, so the
## minimum speed lands it on `target` instead of creeping forever.
static func approach(
	current: float, target: float, half_life: float, max_speed: float, min_speed: float, delta: float
) -> float:
	var gap: float = target - current
	if gap == 0.0 or delta <= 0.0:
		return current
	var step: float = clampf(absf(gap) * _blend(half_life, delta), min_speed * delta, max_speed * delta)
	return target if step >= absf(gap) else current + signf(gap) * step


## `approach` for angles in radians, taking the short way round.
static func approach_angle(
	current: float, target: float, half_life: float, max_speed: float, min_speed: float, delta: float
) -> float:
	var gap: float = angle_difference(current, target)
	return current + approach(0.0, gap, half_life, max_speed, min_speed, delta)


## True with the odds of an event that happens `rate` times a second on average landing
## inside this `delta` (a Poisson process), so the odds don't depend on the frame rate.
static func happens(rate: float, delta: float, rng: RandomNumberGenerator) -> bool:
	if rate <= 0.0 or delta <= 0.0:
		return false
	return rng.randf() < 1.0 - exp(-rate * delta)


# --- authoring: decomp numbers to seconds ------------------------------------------------


## The half-life of an `add_calc` that closes `fraction` of the gap once per tick
## (`MathUtil.HALF_FRACTION` closes half every two ticks: about 0.033 s).
static func half_life_from_fraction(fraction: float, rate_hz: float = DecompTime.TICK_HZ) -> float:
	var keep: float = clampf(1.0 - fraction, 0.0, 0.999999)
	if keep <= 0.0:
		return 0.0
	return log(0.5) / log(keep) / rate_hz


## The rate per second of a roll that succeeds with probability `chance` once per tick.
static func rate_from_chance(chance: float, rate_hz: float = DecompTime.TICK_HZ) -> float:
	if chance <= 0.0:
		return 0.0
	if chance >= 1.0:
		return INF
	return -log(1.0 - chance) * rate_hz


static func _blend(half_life: float, delta: float) -> float:
	if half_life <= 0.0:
		return 1.0
	return 1.0 - pow(0.5, maxf(delta, 0.0) / half_life)
