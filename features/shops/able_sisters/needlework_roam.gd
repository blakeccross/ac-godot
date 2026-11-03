class_name NeedleworkRoam
extends RefCounted

## Where Mabel goes in her shop (`ac_npc_needlework_schedule.c_inc`: `area_table`,
## `near_area_table`, `target_pos_table_*`, `aNNW_next_target`, `aNNW_next_target2`).
##
## The floor is cut into ten areas by unit (40 GX); she follows the player from area to
## area through a fixed set of waypoints rather than straight across. Positions here are
## GX (the decomp's units) in the shop's own frame, so callers convert with
## `to_gx` / `to_world`.

const AREA_NUM := 10
const AREA_NONE := 9  ## the unmapped ring around the room: keep the last real area

## `aNNW_next_target` answers: stay put, go to the player, or roam to a waypoint.
const STAY := 0
const TO_PLAYER := 1
const ROAM := 13

## `target_pos_table_x/z` (waypoints 2-12; 0, 1 and 13 are the unused origin).
const TARGET_X: Array[int] = [0, 0, 60, 140, 140, 140, 140, 340, 340, 340, 200, 200, 140, 0]
const TARGET_Z: Array[int] = [0, 0, 180, 180, 60, 140, 220, 60, 140, 220, 240, 300, 100, 0]

## `near_area_table[now_area]`: the areas a player may stand in and still count as close.
const NEAR_AREA: Array = [
	[1, 9, 9, 9, 9],
	[0, 3, 9, 9, 9],
	[3, 9, 9, 9, 9],
	[1, 2, 4, 7, 8],
	[3, 5, 6, 9, 9],
	[4, 7, 8, 9, 9],
	[4, 9, 9, 9, 9],
	[3, 5, 9, 9, 9],
	[3, 5, 9, 9, 9],
]

## `area_table[uz * 10 + ux]`.
const AREA_TABLE: Array[int] = [
	9, 9, 9, 9, 9, 9, 9, 9, 9, 9,
	9, 9, 9, 3, 7, 7, 7, 7, 5, 9,
	9, 2, 2, 3, 9, 9, 9, 9, 5, 9,
	9, 9, 9, 3, 8, 8, 8, 8, 5, 9,
	9, 0, 1, 3, 9, 9, 9, 9, 5, 9,
	9, 0, 9, 3, 4, 4, 4, 4, 5, 9,
	9, 0, 9, 4, 4, 4, 4, 4, 5, 9,
	9, 9, 9, 9, 6, 6, 9, 9, 9, 9,
	9, 9, 9, 9, 6, 6, 9, 9, 9, 9,
	9, 9, 9, 9, 9, 9, 9, 9, 9, 9,
]

## The shop keeps the acre origin: world = GX · 0.05 − 16 on both axes.
const ORIGIN := Vector2(-16.0, -16.0)

## `actor->pl_area` / `now_area`: the last real areas, kept across the unmapped ring.
var player_area: int = 6
var now_area: int = 4
## `actor->_9B6`: the waypoint she is heading for (or last visited).
var target: int = 0


static func to_gx(world: Vector3) -> Vector2:
	return (Vector2(world.x, world.z) - ORIGIN) / FieldCatalog.GX_TO_METERS


static func to_world(gx: Vector2, y: float = 0.0) -> Vector3:
	var p: Vector2 = gx * FieldCatalog.GX_TO_METERS + ORIGIN
	return Vector3(p.x, y, p.y)


static func target_gx(idx: int) -> Vector2:
	return Vector2(TARGET_X[idx], TARGET_Z[idx])


## `aNNW_get_area`: the area a GX position is in (`AREA_NONE` outside the table).
static func area_at(gx: Vector2) -> int:
	var ux: int = floori(gx.x / 40.0)
	var uz: int = floori(gx.y / 40.0)
	if ux < 0 or uz < 0 or ux >= AREA_NUM or uz >= AREA_NUM:
		return AREA_NONE
	return AREA_TABLE[uz * AREA_NUM + ux]


## Refresh `player_area` / `now_area` from where both stand, holding the last real area
## while either is in the unmapped ring.
func track(player_gx: Vector2, self_gx: Vector2) -> void:
	var pa: int = area_at(player_gx)
	var na: int = area_at(self_gx)
	player_area = player_area if pa == AREA_NONE else pa
	now_area = now_area if na == AREA_NONE else na


## `aNNW_next_target`. `waiting_on_trade` is think OMATIKUDASI / 2, which tightens the
## close range from 115 to 55 GX. `distance_gx` is the planar player distance.
func next_target(player_gx: Vector2, self_gx: Vector2, distance_gx: float, waiting_on_trade: bool) -> int:
	track(player_gx, self_gx)
	if (player_area == 0 or player_area == 1) and now_area == 1:
		return STAY
	var close: float = 55.0 if waiting_on_trade else 115.0
	if distance_gx < close:
		if player_area == now_area:
			return STAY
		for near: int in NEAR_AREA[now_area]:
			if near == player_area:
				return STAY
	if player_area == now_area:
		return TO_PLAYER
	return ROAM


## `aNNW_next_target2`: the next waypoint toward the player's area from where she is.
## Reads and writes `target` (`_9B6`, the waypoint she just left).
func next_waypoint(player_gx: Vector2, self_gx: Vector2) -> int:
	track(player_gx, self_gx)
	match now_area:
		0:
			return 3 if target == 2 else 2
		1:
			return 2 if player_area == 0 else 3
		2:
			return 12
		3:
			return _from_area_3(player_gx)
		4:
			if player_area == 6:
				return 11 if target == 10 else 10
			return 9 if player_gx.x > 200.0 else 6
		5:
			return _from_area_5(player_gx)
		6:
			return 10
		7:
			return 7 if player_gx.x > 200.0 else 4
		8:
			return 8 if player_gx.x > 200.0 else 5
	return ROAM


## `aNNW_next_target2_aNNW_04`.
func _from_area_3(player_gx: Vector2) -> int:
	match player_area:
		0:
			return 2 if target == 3 else 3
		1:
			return 3
		2:
			return 12
		4, 6:
			return 10 if target == 6 else 6
		5:
			if player_gx.y <= 100.0:
				return 7 if target == 4 else 4
			if player_gx.y <= 180.0:
				return 8 if target == 5 else 5
			return 9 if target == 6 else 6
		7:
			return 7 if target == 4 else 4
		8:
			return 8 if target == 5 else 5
	return 0


## `aNNW_next_target2_aNNW_06`.
func _from_area_5(player_gx: Vector2) -> int:
	if player_gx.y <= 100.0:
		return 4 if target == 7 else 7
	if player_gx.y <= 180.0:
		return 5 if target == 8 else 8
	if target == 9:
		return 10 if (player_area == 4 or player_area == 6) else 6
	return 9


# --- the `aNNW_MY_PROC_*` state machine ----------------------------------------------

## `aNNW_MY_PROC_*`: wait, run at the player, turn toward the player, run to a waypoint,
## turn toward a waypoint.
enum Proc { WAIT, PLAYER, TURN_P, RUN, TURN }
## What her body is doing (`aNPC_ACT_WAIT` / `_RUN` / `_TURN`).
enum Act { WAIT, RUN, TURN }

## `aNPC_spd_data` run: 3.0 GX per tick-pair → 4.5 m/s, `aNPC_position_move` accel / decel.
const RUN_SPEED := 4.5
const RUN_ACCEL := 13.5
const RUN_DECEL := 27.0
## `mv_add_angl × 30`: 11.25° (turn act, run) and 5.625° (turning to face the player).
const SPIN_TURN := 5.89
const FACE_TURN := 2.945
## `aNPC_check_arrive_destination`: squared range 72 GX² → ~0.42 m.
const ARRIVE := 0.42
## `proc_delay_frames = 5` play ticks between re-aims at a moving player.
const REAIM_DELAY := 5.0 * DecompTime.TICK_SEC
## Wait / trade-wait: `aNNW_my_proc_wait` re-routes once the player is this far (GX).
const WAIT_RANGE := 120.0
const TRADE_WAIT_RANGE := 60.0
## No progress for this long ends the action, standing in for `aNPC_avoid_wall`.
const STUCK_SECONDS := 1.0

var proc: Proc = Proc.WAIT
var act: Act = Act.WAIT
## `think_idx` OMATIKUDASI / 2: the player pressed A at a display and she is coming over.
var waiting_on_trade: bool = false

var velocity: Vector3 = Vector3.ZERO  ## planar m/s the body should move at
var yaw: float = 0.0  ## where it faces, radians
var moving: bool = false

var _act_target: Vector2 = Vector2.ZERO  ## GX
var _act_done: bool = false
var _delay: float = 0.0
var _speed: float = 0.0
var _stuck: float = 0.0
var _last_pos: Vector3 = Vector3.INF


func reset(start_yaw: float) -> void:
	proc = Proc.WAIT
	act = Act.WAIT
	waiting_on_trade = false
	velocity = Vector3.ZERO
	yaw = start_yaw
	moving = false
	target = 0
	_act_done = false
	_speed = 0.0
	_stuck = 0.0
	_last_pos = Vector3.INF


## True once she has come to a stop beside the player (`aNNW_omatikudasai2`: `my_proc_idx`
## is back to WAIT), which is when the display trade opens.
func is_waiting() -> bool:
	return proc == Proc.WAIT


## One step of `aNNW_my_proc_main` plus the body action it asks for.
func tick(delta: float, self_pos: Vector3, player_pos: Vector3, self_yaw: float) -> void:
	yaw = self_yaw
	var self_gx: Vector2 = to_gx(self_pos)
	var player_gx: Vector2 = to_gx(player_pos)
	var dist: float = self_gx.distance_to(player_gx)
	_track_stuck(delta, self_pos)
	match proc:
		Proc.WAIT:
			var wait_range: float = TRADE_WAIT_RANGE if waiting_on_trade else WAIT_RANGE
			if dist >= wait_range:
				if next_target(player_gx, self_gx, dist, waiting_on_trade) == TO_PLAYER:
					_init_proc(Proc.TURN_P, self_gx, player_gx)
				else:
					_init_proc(Proc.TURN, self_gx, player_gx)
			else:
				_face(player_gx, self_gx, FACE_TURN, delta)
		Proc.PLAYER:
			match next_target(player_gx, self_gx, dist, waiting_on_trade):
				TO_PLAYER:
					if _delay > 0.0:
						_delay -= delta
					else:
						_init_proc(Proc.PLAYER, self_gx, player_gx)
				STAY:
					_init_proc(Proc.WAIT, self_gx, player_gx)
				_:
					_init_proc(Proc.TURN, self_gx, player_gx)
		Proc.TURN_P:
			if act == Act.TURN and _act_done:
				_init_proc(Proc.PLAYER, self_gx, player_gx)
		Proc.RUN:
			match next_target(player_gx, self_gx, dist, waiting_on_trade):
				TO_PLAYER:
					_init_proc(Proc.TURN_P, self_gx, player_gx)
				STAY:
					_init_proc(Proc.WAIT, self_gx, player_gx)
				_:
					if act == Act.RUN and _act_done:
						_init_proc(Proc.TURN, self_gx, player_gx)
		Proc.TURN:
			if act == Act.TURN and _act_done:
				_init_proc(Proc.RUN, self_gx, player_gx)
	_run_act(delta, self_pos)


func _init_proc(next: Proc, self_gx: Vector2, player_gx: Vector2) -> void:
	proc = next
	match next:
		Proc.WAIT:
			target = 0
			_request(Act.WAIT, self_gx)
		Proc.PLAYER:
			target = 1
			_delay = REAIM_DELAY
			_request(Act.RUN, player_gx)
		Proc.TURN_P:
			## `aNNW_my_proc_turn_p_init`. Retail tests `ABS(diff < 90°)`, so any bearing
			## that isn't 90°-180° to the left of her counts as "ahead" and she runs.
			if _signed_turn(player_gx, self_gx) < PI * 0.5:
				_init_proc(Proc.PLAYER, self_gx, player_gx)
			else:
				target = 1
				_request(Act.TURN, player_gx)
		Proc.RUN:
			_request(Act.RUN, target_gx(target))
		Proc.TURN:
			target = next_waypoint(player_gx, self_gx)
			## `aNNW_my_proc_turn_init`: the same `ABS(diff < 90°)` slip.
			if _signed_turn(target_gx(target), self_gx) < PI * 0.5:
				_init_proc(Proc.RUN, self_gx, player_gx)
			else:
				_request(Act.TURN, target_gx(target))


func _request(next: Act, at_gx: Vector2) -> void:
	act = next
	_act_target = at_gx
	_act_done = false
	_stuck = 0.0


## Radians from her heading to `at_gx` (`DIFF_SHORT_ANGLE`, signed).
func _signed_turn(at_gx: Vector2, self_gx: Vector2) -> float:
	var d: Vector2 = at_gx - self_gx
	if d.length_squared() < 0.0001:
		return 0.0
	return angle_difference(yaw, atan2(d.x, d.y))


func _face(at_gx: Vector2, self_gx: Vector2, rate: float, delta: float) -> void:
	var d: Vector2 = at_gx - self_gx
	if d.length_squared() > 0.0001:
		yaw = _turn_toward(yaw, atan2(d.x, d.y), rate * delta)
	velocity = Vector3.ZERO
	moving = false


static func _turn_toward(from: float, to: float, step: float) -> float:
	var diff: float = angle_difference(from, to)
	if absf(diff) <= step:
		return to
	return from + signf(diff) * step


func _run_act(delta: float, self_pos: Vector3) -> void:
	var self_gx: Vector2 = to_gx(self_pos)
	match act:
		Act.WAIT:
			_speed = move_toward(_speed, 0.0, RUN_DECEL * delta)
			velocity = Vector3(sin(yaw), 0.0, cos(yaw)) * _speed
			moving = _speed > 0.05
		Act.TURN:
			var d: Vector2 = _act_target - self_gx
			if d.length_squared() > 0.0001:
				yaw = _turn_toward(yaw, atan2(d.x, d.y), SPIN_TURN * delta)
				_act_done = absf(angle_difference(yaw, atan2(d.x, d.y))) < 0.001
			else:
				_act_done = true
			_speed = move_toward(_speed, 0.0, RUN_DECEL * delta)
			velocity = Vector3(sin(yaw), 0.0, cos(yaw)) * _speed
			moving = _speed > 0.05
		Act.RUN:
			var d: Vector2 = _act_target - self_gx
			var arrive_gx: float = ARRIVE / FieldCatalog.GX_TO_METERS
			if d.length() < arrive_gx or _stuck >= STUCK_SECONDS:
				_act_done = true
				_speed = move_toward(_speed, 0.0, RUN_DECEL * delta)
			else:
				yaw = _turn_toward(yaw, atan2(d.x, d.y), SPIN_TURN * delta)
				_speed = move_toward(_speed, RUN_SPEED, RUN_ACCEL * delta)
			velocity = Vector3(sin(yaw), 0.0, cos(yaw)) * _speed
			moving = _speed > 0.05


func _track_stuck(delta: float, self_pos: Vector3) -> void:
	if act == Act.RUN and _last_pos != Vector3.INF and self_pos.distance_to(_last_pos) < RUN_SPEED * delta * 0.15:
		_stuck += delta
	else:
		_stuck = 0.0
	_last_pos = self_pos
