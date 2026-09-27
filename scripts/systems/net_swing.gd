class_name NetSwing
extends RefCounted

## The net's hold-and-release verb, one 60 Hz tick at a time. Behavioral port of
## `m_player_main_ready_net` / `ready_walk_net` / `slip_net` / `swing_net` / `stop_net`.
##
## A with the net equipped does not swing: it raises the net (`READY`, `KAMAE_WAIT_M1`).
## While A stays down the player can creep with it raised (`READY_WALK`); pressing A out of a
## dash skids first (`SLIP`). Letting go of A is what swings (`SWING`, `NET_SWING1`). From
## keyframe 6 on, every tick tests the net head against the insects' catch spheres; the swing
## runs to its last keyframe even after a catch. It ends in `PULL` (something is in the net —
## the player's catch sequence takes over) or `STOP` (empty; the body freezes on its last
## pose while the net plays `SWING_WAIT1`, then back to the wait). The net's line hitting a
## wall, the ground or a villager cuts the swing short with `AMI_HIT`.
##
## Pure logic: the player feeds input and a `Probe` of this tick's net pose, and applies
## `speed_gx` / `yaw` / the clip fields. Nothing here reads the scene.

enum State { NONE, READY, READY_WALK, SLIP, SWING, STOP, PULL }

## `mCoBG_LINE_CHECK_*` bits from `mCoBG_LineCheck_RemoveFg(…, 7)` on the net's line.
const LINE_WALL := 1
const LINE_GROUND := 2
const LINE_WATER := 4
const LINE_UNDERWATER := 8

const ANIM_READY := &"ply_1_kamae_wait_m1"
const ANIM_READY_WALK := &"ply_1_kamae_move_m1"
const ANIM_SLIP := &"ply_1_kamae_slip_m1"
const ANIM_SWING := &"ply_1_net_swing1"
## Item clips (`mPlayer_ITEM_DATA_*` on `tol_net_1`). `SetupItem_Base2` takes item-data
## indices in the slot the decomp labels as a player anim: `PICKUP1` (7) is `NET_SWING`,
## `GET_CHANGE1` (11) is `SWING_WAIT`.
const TOOL_READY := &"kamae_main_m1"
const TOOL_SWING := &"net_swing1"
const TOOL_STOP := &"swing_wait1"

## Keyframe counts (`cKF_ba_r_ply_1_net_swing1`, `cKF_ba_r_tol_net_1_swing_wait1`).
const SWING_FRAMES := 10.0
const STOP_ITEM_FRAMES := 21.0
## `InitAnimation_Base*` frame speed: keyframes per tick.
const FRAME_SPEED := 0.5
## `Player_actor_CatchSomethingCheck_Swing_net` / `HitBGCheck_Swing_net`: `current_frame > 6`.
const CATCH_AFTER_FRAME := 6.0

## `Player_actor_Item_CheckLocalCapture_forNet`: the net's reach added to the insect's own
## catch range (21 for the golden net, which is not in the game yet). `net_top_col_pos` and
## `net_bot_col_pos` are the same point, so the capsule test reduces to a sphere.
const CATCH_REACH_GX := 15.0

## `Player_actor_Item_draw_net`: the net's points, off the hand matrix after
## `Matrix_rotateXYZ(0, 3000, 0)`, at these model-space Z offsets × the player's 0.01 scale.
const NET_YAW_S16 := 3000.0
const NET_START_GX := -24.0
const NET_END_GX := 55.0
const NET_POS_GX := 40.0

## Per-tick brakes (`Player_actor_Movement_Base_Braking_common`).
const READY_BRAKE := 0.23925
const SLIP_BRAKE := 0.23925
const SWING_BRAKE := 0.32625001

## `Player_actor_Movement_Ready_walk_net` / `CulcAnimation_Ready_walk_net`.
const WALK_MAX_GX := 1.8
const WALK_ACCEL := 0.60899997
const WALK_DECEL := 0.32625002
const WALK_ANIM_COEF := 0.252
const WALK_ANIM_MIN := 0.22


## What the player measured for this tick. Positions are world metres.
class Probe:
	## `player->net_pos`.
	var net_pos: Vector3 = Vector3.ZERO
	## `mCoBG_LINE_CHECK_*` bits for the net's start → end line.
	var line_bits: int = 0
	## `Player_actor_Check_OBJtoLine_forItem_net`: the actor the net's triangle touched.
	var hit_actor: Object = null
	## `item_net_catch_*_request_table`: what registered this tick, in registration order.
	var candidates: Array[Candidate] = []


## One `Set_Item_net_catch_request_table` row.
class Candidate:
	var target: Object = null
	var position: Vector3 = Vector3.ZERO
	var range_gx: float = 0.0

	func _init(p_target: Object = null, p_position: Vector3 = Vector3.ZERO, p_range: float = 0.0) -> void:
		target = p_target
		position = p_position
		range_gx = p_range


var state: State = State.NONE
## Set on the tick a state starts; the player reads and clears it to swap clips.
var state_changed: bool = false
## `actor->speed` (GX per 30 fps frame) and `world.angle.y` (radians).
var speed_gx: float = 0.0
var yaw: float = 0.0
## Body keyframe (`keyframe0.frame_control`), 1-based like cKF.
var frame: float = 1.0
var frame_speed: float = FRAME_SPEED
## Net keyframe during `STOP` (`item_keyframe`).
var item_frame: float = 1.0
## `item_net_catch_label` — the first candidate the net took, or null.
var caught: Object = null
## `main_data.swing_net.swing_timer`: +0.5 every tick the catch check runs.
var swing_timer: float = 0.0
## Everything this tick asked the scene to do, in order: `&"furi"` (swing whoosh),
## `&"get"` (catch SE), `&"hit"` (`AMI_HIT` + rumble), `&"splash"` (net dipped in water),
## `&"stop_net"` (`Check_StopNet` fires for bugs and fish), `&"slip"` (skid SE + dust).
var events: Array[StringName] = []
## The actor the net hit when the swing was cut short (`Player_actor_CheckAndSet_UZAI_forNpc`).
var hit_actor: Object = null

var _anim_stopped: bool = false


func is_active() -> bool:
	return state != State.NONE and state != State.PULL


## `Player_actor_request_main_ready_net` (from wait / walk / run) or `_slip_net` (from dash).
func begin(from_dash: bool, start_speed_gx: float, start_yaw: float) -> void:
	speed_gx = start_speed_gx
	yaw = start_yaw
	caught = null
	hit_actor = null
	swing_timer = 0.0
	events.clear()
	_set_state(State.SLIP if from_dash else State.READY)
	if from_dash:
		events.append(&"slip")


func cancel() -> void:
	state = State.NONE
	state_changed = false
	events.clear()


## One play-loop update. `stick` is `move_pR`, `wish_yaw` the stick's world angle,
## `axes_active` `move_pX || move_pY`, `over_norm` the uphill speed divisor and `wall_ratio`
## how much of last tick's step the walls let through (1 = free).
func tick(
	a_held: bool,
	stick: float,
	wish_yaw: float,
	axes_active: bool,
	probe: Probe = null,
	over_norm: float = 1.0,
	wall_ratio: float = 1.0
) -> void:
	events.clear()
	match state:
		State.READY:
			_tick_ready(a_held, axes_active)
		State.READY_WALK:
			_tick_ready_walk(a_held, stick, wish_yaw, axes_active, over_norm, wall_ratio)
		State.SLIP:
			_tick_slip(a_held)
		State.SWING:
			_tick_swing(probe if probe != null else Probe.new())
		State.STOP:
			_tick_stop()


## World position of a point on the net's shaft, from the hand joint's world transform.
static func net_point(hand: Transform3D, along_gx: float) -> Vector3:
	var basis: Basis = hand.basis.orthonormalized() * Basis(Vector3.UP, MLib.s16_to_rad(NET_YAW_S16))
	return hand.origin + basis * Vector3(0.0, 0.0, along_gx * FieldCatalog.GX_TO_METERS)


## `Player_actor_Item_CheckLocalCapture_forNet` with coincident top and bottom points.
static func in_reach(net_pos: Vector3, target: Vector3, range_gx: float) -> bool:
	var reach: float = (CATCH_REACH_GX + range_gx) * FieldCatalog.GX_TO_METERS
	return net_pos.distance_squared_to(target) <= reach * reach


func _tick_ready(a_held: bool, axes_active: bool) -> void:
	speed_gx = maxf(speed_gx - READY_BRAKE, 0.0)
	frame_speed = FRAME_SPEED
	## `request_proc_index_fromReady_net`: release swings, the stick walks.
	if not a_held:
		_begin_swing()
	elif axes_active:
		_set_state(State.READY_WALK)


func _tick_ready_walk(
	a_held: bool, stick: float, wish_yaw: float, axes_active: bool, over_norm: float, wall_ratio: float
) -> void:
	var mod: float = PlayerLocomotion.turn_mod(stick)
	yaw = MLib.short_angle2(
		yaw, wish_yaw, 1.0 - sqrt(1.0 - mod), PlayerLocomotion.TURN_MAX_RAD, PlayerLocomotion.TURN_MIN_RAD
	)
	var norm: float = over_norm if over_norm > 0.0 else 1.0
	var target: float = (WALK_MAX_GX * stick) / norm
	var aligned: float = cos(absf(angle_difference(yaw, wish_yaw)))
	target = 0.0 if aligned <= 0.0 else target * aligned
	if speed_gx < target:
		speed_gx = minf(speed_gx + WALK_ACCEL, target)
	elif speed_gx > target:
		speed_gx = maxf(speed_gx - WALK_DECEL, target)
	## `CulcAnimation_Ready_walk_net`.
	var sp: float = WALK_ANIM_COEF * sqrt(maxf(speed_gx * norm, 0.0) / WALK_MAX_GX)
	if wall_ratio < 1.0:
		sp *= sqrt(clampf(wall_ratio, 0.0, 1.0))
	frame_speed = maxf(sp, WALK_ANIM_MIN)
	## `request_proc_index_fromReady_walk_net`: swing (22) outranks settling back (13).
	if not a_held:
		_begin_swing()
	elif speed_gx == 0.0 and not axes_active:
		_set_state(State.READY)


func _tick_slip(a_held: bool) -> void:
	speed_gx = maxf(speed_gx - SLIP_BRAKE, 0.0)
	frame_speed = FRAME_SPEED
	if not a_held:
		_begin_swing()
	elif speed_gx == 0.0:
		_set_state(State.READY)


func _begin_swing() -> void:
	_set_state(State.SWING)
	frame = 1.0
	frame_speed = FRAME_SPEED
	_anim_stopped = false
	caught = null
	hit_actor = null
	swing_timer = 0.0
	events.append(&"furi")


func _tick_swing(probe: Probe) -> void:
	## Both checks read the keyframe before this tick advances it.
	var hit: bool = false
	var hit_by: Object = null
	if frame > CATCH_AFTER_FRAME:
		if probe.hit_actor != null:
			hit = true
			hit_by = probe.hit_actor
		else:
			if probe.line_bits & (LINE_WATER | LINE_UNDERWATER):
				events.append(&"splash")
			if probe.line_bits & (LINE_WALL | LINE_GROUND):
				hit = true
	var check_type: int = _catch_check(probe)
	speed_gx = maxf(speed_gx - SWING_BRAKE, 0.0)
	var ended: bool = false
	if hit:
		## `CulcAnimation_Swing_net` with a hit: step back half a keyframe instead.
		frame -= FRAME_SPEED
	else:
		ended = _play_stop_base2(SWING_FRAMES)
	if not ended and not hit:
		return
	if check_type != 0:
		_set_state(State.PULL)
		events.append(&"stop_net")
		if check_type == 2 and hit:
			events.append(&"hit")
		return
	_set_state(State.STOP)
	hit_actor = hit_by
	item_frame = 1.0
	events.append(&"stop_net")
	if hit:
		events.append(&"hit")


## `Player_actor_CatchSomethingCheck_common`: 0 = too early, 1 = caught this tick,
## 2 = already holding something.
func _catch_check(probe: Probe) -> int:
	if frame <= CATCH_AFTER_FRAME:
		return 0
	swing_timer += 0.5
	if caught != null:
		return 2
	for candidate: Candidate in probe.candidates:
		if candidate == null or candidate.target == null:
			continue
		if in_reach(probe.net_pos, candidate.position, candidate.range_gx):
			caught = candidate.target
			events.append(&"get")
			return 1
	return 0


func _tick_stop() -> void:
	speed_gx = maxf(speed_gx - SWING_BRAKE, 0.0)
	## `Player_actor_Item_main_net_stop`: back to the wait on the tick `SWING_WAIT1` stops.
	if _play_stop_item(STOP_ITEM_FRAMES):
		_set_state(State.NONE)


## `cKF_FrameControl_play` in stop mode, as `Player_actor_CulcAnimation_Base2` reads it: the
## tick the clip reaches its end only zeroes the speed; the next one reports the end.
func _play_stop_base2(end_frame: float) -> bool:
	if _anim_stopped:
		return true
	if _advance_stop(end_frame):
		_anim_stopped = true
	return false


## `Player_actor_Item_CulcAnimation_Base2`: true on the tick the item clip stops.
func _play_stop_item(end_frame: float) -> bool:
	if item_frame == end_frame:
		return true
	if item_frame < end_frame and item_frame + FRAME_SPEED >= end_frame:
		item_frame = end_frame
		return true
	item_frame += FRAME_SPEED
	return false


func _advance_stop(end_frame: float) -> bool:
	if frame == end_frame:
		return true
	if frame < end_frame and frame + frame_speed >= end_frame:
		frame = end_frame
		return true
	frame += frame_speed
	return false


func _set_state(next: State) -> void:
	state = next
	state_changed = true
