class_name AcreCamera
extends RefCounted

## Outdoor `Camera2` (`m_camera2.c`), in decomp GX. The look-at centre follows the player's eye
## but is held inside a box in the player's current acre (`Camera2_GetBorderScale`, border size
## 110), so the view never shows the next acre until the player wades into it. It eases toward
## that goal with `add_calc(0.134, max 8.75, min 0.25)` a tick, here `Motion.approach` on
## `delta`. A wade moves it to the next acre's box on the same 0.6 s ease as the player
## (`Camera2_main_Wade`).

const BORDER := 110.0
const UNIT_Z := 40.0
## `Camera2_GetUnderBorderAdjust` outdoors.
const UNDER_ADJUST := -15.0
const FRACTION := 0.13397461
const MAX_STEP := 8.75
const MIN_STEP := 0.25
## `Camera2_Normal_Swing`: pitch lift on the rail row (block z 1), short-angle units.
const SWING := 250.0
## `Camera2_MoveDirectionAngleXYZ`: `add_calc_short_angle2(dir.x, goal, 0.0513, 11000, 100)`.
const PITCH_FRACTION := 0.051316679
const PITCH_MAX_STEP := 11000.0 * MathUtil.S16
const PITCH_MIN_STEP := 100.0 * MathUtil.S16
## The same eases in seconds: GX (or radians) a second, from the per-tick steps above.
static var HALF_LIFE: float = Motion.half_life_from_fraction(FRACTION)
const MAX_SPEED := MAX_STEP * 60.0
const MIN_SPEED := MIN_STEP * 60.0
static var PITCH_HALF_LIFE: float = Motion.half_life_from_fraction(PITCH_FRACTION)
const PITCH_MAX_SPEED := PITCH_MAX_STEP * 60.0
const PITCH_MIN_SPEED := PITCH_MIN_STEP * 60.0


## `Camera2_GetBorderScale(scale 1)` for `block`: `{x_min, x_max, z_min, z_max}` of the centre.
## (The decomp calls these x1 / x0 and z1 / z0.)
static func box(block: Vector2i) -> Dictionary:
	var base: Vector2 = TownSpace.block_base(block)
	return {
		"x_min": base.x + BORDER,
		"x_max": base.x + TownSpace.BLOCK_GX - BORDER,
		"z_min": base.y + BORDER + UNIT_Z,
		"z_max": base.y + TownSpace.BLOCK_GX - (BORDER + UNDER_ADJUST),
	}


## `Camera2_main_Normal_SetEndCenterPos_fromPlayer`: the player's eye clamped into the box of
## the acre the player stands in.
static func goal(eye_gx: Vector3, player_gx: Vector3) -> Vector3:
	var b: Dictionary = box(TownSpace.block_of(player_gx))
	var out := eye_gx
	out.x = clampf(out.x, b["x_min"], b["x_max"])
	out.z = clampf(out.z, b["z_min"], b["z_max"])
	return out


## `Camera2_ChangeCameraPos_inBlock`: the wade's camera goal. `pos` is the player's eye at the
## wade's end; the box is still the one of the acre being left, so the jump uses the decomp's
## literal offsets (they land 40 GX past the far box edge when wading north; the normal camera
## then eases back).
static func wade_goal(pos: Vector3, player_gx: Vector3) -> Vector3:
	var b: Dictionary = box(TownSpace.block_of(player_gx))
	var x_hi: float = b["x_max"]
	var x_lo: float = b["x_min"]
	var z_lo: float = b["z_min"]
	var z_hi: float = b["z_max"]
	var out := pos
	if pos.x < x_lo:
		if pos.x < x_lo - BORDER:
			out.x = x_lo - 2.0 * BORDER
		elif out.x < x_lo:
			out.x = x_lo
	elif pos.x > x_hi:
		if pos.x > x_hi + BORDER:
			out.x = x_hi + 2.0 * BORDER
		elif out.x > x_hi:
			out.x = x_hi
	if pos.z < z_lo:
		if pos.z < z_lo - (BORDER + UNIT_Z):
			out.z = z_lo - 2.0 * BORDER - UNIT_Z - UNDER_ADJUST
		elif out.z < z_lo:
			out.z = z_lo
	elif pos.z > z_hi:
		if pos.z > BORDER + UNDER_ADJUST + z_hi:
			out.z = z_hi + 2.0 * BORDER + UNIT_Z + UNDER_ADJUST
		elif out.z > z_hi:
			out.z = z_hi
	return out


## `delta` seconds of the centre's `add_calc`, axis by axis.
static func follow(center: Vector3, target: Vector3, delta: float) -> Vector3:
	return Vector3(
		Motion.approach(center.x, target.x, HALF_LIFE, MAX_SPEED, MIN_SPEED, delta),
		Motion.approach(center.y, target.y, HALF_LIFE, MAX_SPEED, MIN_SPEED, delta),
		Motion.approach(center.z, target.z, HALF_LIFE, MAX_SPEED, MIN_SPEED, delta),
	)


static func add_calc(value: float, target: float, fraction: float = FRACTION, max_step: float = MAX_STEP, min_step: float = MIN_STEP) -> float:
	if value == target:
		return value
	var step: float = fraction * (target - value)
	if step <= -min_step or step >= min_step:
		step = clampf(step, -max_step, max_step)
	else:
		step = min_step if step > 0.0 else -min_step
	var out: float = value + step
	if (step > 0.0 and out > target) or (step < 0.0 and out < target):
		out = target
	return out


## `Camera2_Normal_Swing`: extra pitch (radians, negative = lower) on the rail row's north half.
static func swing(eye_gx: Vector3, player_gx: Vector3) -> float:
	var block: Vector2i = TownSpace.block_of(eye_gx)
	if block.y != 1:
		return 0.0
	var b: Dictionary = box(TownSpace.block_of(player_gx))
	var z_mid: float = (float(b["z_min"]) + float(b["z_max"])) * 0.5
	var half: float = z_mid - float(b["z_min"])
	if is_zero_approx(half):
		return 0.0
	var ratio: float = clampf((eye_gx.z - z_mid) / half, -1.0, 1.0)
	if ratio >= 0.0:
		return 0.0
	return ratio * SWING * MathUtil.S16


## `delta` seconds of the pitch ease (`Camera2_MoveDirectionAngleXYZ`).
static func follow_pitch(current: float, goal: float, delta: float) -> float:
	return Motion.approach_angle(current, goal, PITCH_HALF_LIFE, PITCH_MAX_SPEED, PITCH_MIN_SPEED, delta)


## `delta` seconds of a wade (`Camera2_MoveDirectionAngleXYZ_morph`): close `delta / time_left`
## of the gap, so the pitch lands on the goal exactly when the scroll does.
static func morph_pitch(current: float, goal: float, time_left: float, delta: float) -> float:
	if time_left <= delta:
		return goal
	return current + angle_difference(current, goal) * delta / time_left
