class_name TreeSway
extends RefCounted

## EffectBG tree sway (`cKF_ba_r_ef_*_shakeS` / `shakeL`): Hermite keyframes on the trunk
## joint's Z rotation, sampled at 30 fps (`frame_control.speed = 0.5` on the 60 Hz tick).
## Key = Vector3(frame, degrees, degrees/second); the tables store the original s16
## value / tangent in tenths of a degree.
##
## Which set a tree plays is `summer_tree_anime_tbl[variant][type]` and its cedar / palm
## siblings: medium and large hardwood + palm share one curve, a full hardwood / palm
## and every cedar share another (cedar's small shake is a little wider).

## `efbg->timer_max` on the 60 Hz tick.
const SMALL_TICKS := 18
const LARGE_TICKS := 82

## `tree3` / `tree4` / `palm3` / `palm4` shakeS.
const _MED_S: Array[Vector3] = [
	Vector3(1, 0.0, 61.6),
	Vector3(3, 3.0, -5.2),
	Vector3(4, 1.7, -55.6),
	Vector3(6, -2.0, 3.1),
	Vector3(8, 1.0, 7.5),
	Vector3(9, 0.0, -30.0),
]
## `tree3` / `tree4` / `palm3` / `palm4` shakeL.
const _MED_L: Array[Vector3] = [
	Vector3(1, 0.0, 9.4),
	Vector3(3, 1.0, 20.6),
	Vector3(5, 2.0, -9.4),
	Vector3(6, 1.1, -45.0),
	Vector3(9, -4.0, 9.4),
	Vector3(10, -2.4, 75.0),
	Vector3(13, 6.0, -4.7),
	Vector3(14, 4.1, -90.0),
	Vector3(16, -4.1, -90.0),
	Vector3(17, -6.0, 0.0),
	Vector3(19, 0.0, 123.8),
	Vector3(20, 4.1, 90.0),
	Vector3(21, 6.0, 4.7),
	Vector3(24, -2.4, -75.0),
	Vector3(25, -4.0, -9.4),
	Vector3(28, 1.1, 45.0),
	Vector3(29, 2.0, 7.0),
	Vector3(32, -0.5, -22.5),
	Vector3(34, -0.8, 11.2),
	Vector3(37, 0.5, 2.3),
	Vector3(41, 0.0, -2.3),
]
## `tree5` / `palm5` shakeS.
const _FULL_S: Array[Vector3] = [
	Vector3(1, 0.0, 66.3),
	Vector3(3, 3.0, 0.0),
	Vector3(6, -2.0, 0.0),
	Vector3(8, 1.0, 0.0),
	Vector3(9, 0.0, 0.0),
]
## `cedar3` / `cedar4` / `cedar5` shakeS.
const _CEDAR_S: Array[Vector3] = [
	Vector3(1, 0.0, 93.1),
	Vector3(3, 4.0, 0.0),
	Vector3(6, -2.0, 0.0),
	Vector3(8, 1.0, 0.0),
	Vector3(9, 0.0, 0.0),
]
## `tree5` / `palm5` / every cedar shakeL (flat tangents).
const _FULL_L: Array[Vector3] = [
	Vector3(1, 0.0, 0.0),
	Vector3(5, 2.0, 0.0),
	Vector3(9, -4.0, 0.0),
	Vector3(13, 6.0, 0.0),
	Vector3(17, -6.0, 0.0),
	Vector3(21, 6.0, 0.0),
	Vector3(25, -4.0, 0.0),
	Vector3(29, 2.0, 0.0),
	Vector3(33, -1.0, 0.0),
	Vector3(37, 0.5, 0.0),
	Vector3(41, 0.0, 0.0),
]

## `eYoung_Tree_mv`: sapling wobble roll amplitude 2184 s16 = 12°, phase step 0xC68.
const YOUNG_MAX_DEG := 12.0
const YOUNG_PHASE_STEP := TAU * 0xC68 / 65536.0
## `calc_adjust(timer, 0, 0x28, 0, 2184)` — full amplitude from 40 ticks left.
const YOUNG_FULL_TICKS := 40
## `eYoung_Tree_ct` life by `arg0` (EffectBG type): small shake 14, large 82.
const YOUNG_SMALL_TICKS := 14
const YOUNG_LARGE_TICKS := 82


## Keys for a grown tree of `family` at `size` (`TreeUse.Size`, S1 = medium … FULL).
static func keys(family: PlantData.Family, size: int, strong: bool) -> Array[Vector3]:
	var full: bool = size >= TreeUse.Size.FULL
	if family == PlantData.Family.CEDAR:
		return _FULL_L if strong else _CEDAR_S
	if full:
		return _FULL_L if strong else _FULL_S
	return _MED_L if strong else _MED_S


static func first_frame(curve: Array[Vector3]) -> float:
	return curve[0].x


static func last_frame(curve: Array[Vector3]) -> float:
	return curve[curve.size() - 1].x


## `cKF_KeyCalc`: hold outside the keys, Hermite between them with tension = Δframe / 30.
static func sample(curve: Array[Vector3], frame: float) -> float:
	if frame <= curve[0].x:
		return curve[0].y
	var last: int = curve.size() - 1
	if frame >= curve[last].x:
		return curve[last].y
	for i: int in last:
		var a: Vector3 = curve[i]
		var b: Vector3 = curve[i + 1]
		if b.x > frame:
			var span: float = b.x - a.x
			if span <= 0.0:
				return a.y
			var t: float = (frame - a.x) / span
			return _hermite(t, span / DecompTime.FRAME_HZ, a.y, b.y, a.z, b.z)
	return curve[last].y


static func _hermite(
	t: float, tension: float, p0: float, p1: float, m0: float, m1: float
) -> float:
	var t2: float = t * t
	var t3: float = t2 * t
	var blend: float = -2.0 * t3 + 3.0 * t2
	var h10: float = t + t3 - 2.0 * t2
	var h11: float = t3 - t2
	return (1.0 - blend) * p0 + blend * p1 + tension * (h10 * m0 + h11 * m1)


## `eYoung_Tree_mv`: sapling wobble roll (degrees) with `ticks_left` 60 Hz ticks to live
## and the effect's running `phase` (radians, advances `YOUNG_PHASE_STEP` per tick).
static func young_roll(ticks_left: int, phase: float) -> float:
	var full: float = float(YOUNG_FULL_TICKS)
	var amp: float = YOUNG_MAX_DEG * clampf(float(ticks_left) / full, 0.0, 1.0)
	return amp * sin(phase)
