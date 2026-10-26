class_name CreatureRelease
extends RefCounted

## Letting a creature go from the pockets (`mTG_release_proc` →
## `Player_actor_setup_main_Release_creature`). A bug is let go just ahead of the player and
## flies off; a fish is thrown into water found ahead (`mCoBG_SearchWaterLimitDistN`) and
## flies there as a `GYO_RELEASE` actor (`FishRelease`).

## Lengths in metres, from the decomp's GX; speeds in m/s from GX a 30 fps frame.
const GX := FieldCatalog.GX_TO_METERS
const GX_FRAME := GX * DecompTime.FRAME_HZ
## `mSM_IV_OPEN_NORMAL`: water is looked for up to 120 GX ahead in 12 steps.
const SEARCH := 120.0 * GX
const SEARCH_DIVIDE := 12
## Each step's four corners at ±12 GX must be water too, so the fish lands clear of the bank.
const CORNER := 12.0 * GX
## `mPlib_request_main_release_creature_insect_from_submenu`: 7 GX ahead, 13 GX up.
const BUG_AHEAD := 7.0 * GX
const BUG_UP := 13.0 * GX

## `aGYR_actor_ct`: past one unit (40 GX) the fish covers the gap in 60 ticks, lobbed up
## (dy + 450 GX) / 60 GX a frame; inside it, a short lob at 2.5 GX a frame and 0.18 GX a frame
## up for each GX across.
const UNIT := 40.0 * GX
const FAR_FLIGHT := 60.0 * DecompTime.TICK_SEC
const FAR_LIFT := 450.0 * GX
const NEAR_SPEED_XZ := 2.5 * GX_FRAME
const NEAR_LOB := 0.18 * DecompTime.FRAME_HZ
## `aGYR_position_move`: -0.25 GX a frame off the speed every tick (m/s², down).
const GRAVITY := -0.25 * GX_FRAME * DecompTime.TICK_HZ
## `aGYR_check_timer`: shrinks past 140 ticks, gone at 160.
const SHRINK_FROM := 140
const LIFE := 160
## `aGYR_actor_ct`: 0.0126 against the held fish's flat 0.01, widened 1.2× across.
const SCALE_RATIO := 1.26
const WIDTH := 1.2
## `aGYR_move_sub`: the fish noses over to 90° at 0x800 a tick.
const TILT_STEP := 0x800 * TAU / 65536.0


## The first point ahead whose step and four corners are all water, in metres (y left 0),
## or null. `is_water` takes a world position in metres.
static func search_water(is_water: Callable, from: Vector3, yaw: float) -> Variant:
	var step: float = SEARCH / float(SEARCH_DIVIDE)
	var dir := Vector3(sin(yaw), 0.0, cos(yaw))
	var corner: float = CORNER
	var corners: Array[Vector3] = [
		Vector3(corner, 0.0, corner), Vector3(corner, 0.0, -corner),
		Vector3(-corner, 0.0, -corner), Vector3(-corner, 0.0, corner),
	]
	for i: int in SEARCH_DIVIDE + 1:
		var at := Vector3(from.x, 0.0, from.z) + dir * (step * float(i))
		if not bool(is_water.call(at)):
			continue
		var all_water: bool = true
		for off: Vector3 in corners:
			if not bool(is_water.call(at + off)):
				all_water = false
				break
		if all_water:
			return at
	return null


## `aGYR_actor_ct`: the throw's velocity (m/s) from the player's feet to the water point
## (metres).
static func launch_velocity(from: Vector3, water: Vector3) -> Vector3:
	var dx: float = water.x - from.x
	var dz: float = water.z - from.z
	var dy: float = water.y - from.y
	var dist: float = sqrt(dx * dx + dz * dz)
	var speed_xz: float
	var speed_y: float
	if dist > UNIT:
		speed_xz = dist / FAR_FLIGHT
		## (dy + 450) / 60 GX a frame.
		speed_y = maxf((dy + FAR_LIFT) / 60.0 * DecompTime.FRAME_HZ, 0.0)
	else:
		speed_xz = NEAR_SPEED_XZ
		speed_y = dist * NEAR_LOB
	var yaw: float = atan2(dx, dz)
	return Vector3(speed_xz * sin(yaw), speed_y, speed_xz * cos(yaw))


## `aGYR_check_timer`: the scale factor at tick `t` (1 until 140, then 0.89 a tick down to
## 0.006 / 0.0126 of the start and 0.98 a tick after).
static func shrink(t: int) -> float:
	var s: float = 1.0
	for i: int in range(SHRINK_FROM + 1, mini(t, LIFE) + 1):
		s *= 0.89 if s * 0.0126 > 0.006 else 0.98
	return s


## The pockets' tag for a creature (`mTG_TYPE_FIELD_RELEASE`): bugs outdoors, fish when
## water lies ahead.
static func can_release(data: ItemData, outdoors: bool, water_ahead: bool) -> bool:
	if data == null or not outdoors:
		return false
	if data.category == ItemData.Category.BUG:
		return true
	return data.category == ItemData.Category.FISH and water_ahead
