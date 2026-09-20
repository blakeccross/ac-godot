extends Node3D

## A cockroach in the player's house (`ac_house_goki.c`). Runs from the player, hops when
## cornered, dawdles when left alone, and dies when stepped on or when furniture lands on it.
## Timers and speeds keep the decomp's per-frame units at its 30 Hz logic rate (1 speed unit =
## 1.5 m/s; a timer unit is 1/15 s).

signal died

enum Act { AWAY, JUMP_AWAY, WAIT, MOVE, DEAD }

const VISUAL := &"act_m_house_goki"
const TICK_HZ := 30.0
const MPS := 1.5
const TIMER_HZ := 15.0
## `aHG_check_dead`: the player treads on it inside 9 GX while moving.
const STEP_KILL := 9.0 * FieldCatalog.GX_TO_METERS
## `aHG_player_check`: a moving player within 60 GX scares it.
const SCARE := 60.0 * FieldCatalog.GX_TO_METERS
const RADIUS := 0.4
## `position_speed.y = 17`, `gravity = -2` (rising) / `-7` (falling) GX per frame.
const JUMP_VY := 17.0 * FieldCatalog.GX_TO_METERS * TICK_HZ
const G_UP := -2.0 * FieldCatalog.GX_TO_METERS * TICK_HZ * TICK_HZ
const G_DOWN := -7.0 * FieldCatalog.GX_TO_METERS * TICK_HZ * TICK_HZ

var session: IndoorSession
var act: Act = Act.AWAY
var speed_units: float = 0.0
var yaw: float = 0.0
var alpha: float = 255.0
var alive: bool = true

var _timer: float = 0.0
var _timer2: float = 0.0
var _jump_flag: bool = false
var _vy: float = 0.0
var _rng := RandomNumberGenerator.new()
var _visual: Node3D
var _step_se: float = 0.0
var _fade_in: bool = false


func setup(p_session: IndoorSession, fade: bool) -> void:
	session = p_session
	_fade_in = fade
	alpha = 30.0 if fade else 255.0
	_rng.randomize()


func _ready() -> void:
	add_to_group("house_goki")
	_visual = GeneratedVisual.attach(self, VISUAL)
	yaw = _yaw_away_from_player()
	_enter(Act.AWAY)


func _physics_process(delta: float) -> void:
	if session == null:
		return
	_timer = maxf(_timer - delta * TIMER_HZ, 0.0)
	_timer2 = maxf(_timer2 - delta * TIMER_HZ, 0.0)
	if act != Act.DEAD:
		if _fade_in:
			alpha = minf(alpha + 3.5 * TICK_HZ * delta, 255.0)
			if alpha >= 255.0:
				_fade_in = false
		if not _fade_in and _should_die():
			_enter(Act.DEAD)
	_move(delta)
	match act:
		Act.AWAY:
			_tick_away()
		Act.JUMP_AWAY:
			_tick_jump()
		Act.WAIT:
			_tick_wait()
		Act.MOVE:
			_tick_move()
		Act.DEAD:
			_tick_dead(delta)
	rotation.y = yaw
	if _visual != null:
		_visual.visible = alpha > 0.0
		_set_alpha(alpha / 255.0)


## --- state changes ----------------------------------------------------------------------


func _enter(next: Act) -> void:
	act = next
	match next:
		Act.AWAY:
			_timer = 20.0 + _rng.randf() * 20.0
			_timer2 = 0.0
			_jump_flag = false
			speed_units = 8.0
		Act.JUMP_AWAY:
			## `aHG_jump_away_init`: leaves 22.5° off straight away from the player.
			yaw = _player_yaw() + PI + deg_to_rad(22.5)
			_vy = JUMP_VY
			speed_units = 5.0
			Audio.play_se(&"goki_jump_away", self)
		Act.WAIT:
			yaw = _yaw_away_from_player()
			speed_units = 0.0
		Act.MOVE:
			_timer = 5.0 + _rng.randf() * 5.0
			_jump_flag = false
			var target := Vector2(80.0 - _rng.randf() * 160.0, 80.0 - _rng.randf() * 160.0) * FieldCatalog.GX_TO_METERS
			yaw = atan2(target.x, target.y)
			speed_units = 4.0
		Act.DEAD:
			alive = false
			_timer = 40.0
			speed_units = 0.0
			Audio.play_se(&"goki_dead", self)
			died.emit()


func _tick_away() -> void:
	if _timer <= 0.0 and not _jump_flag and not _player_scares():
		_timer = 20.0 + _rng.randf() * 20.0
		_enter(Act.WAIT)
		return
	if _hit_wall:
		if _timer2 <= 0.0:
			var chance: float = 0.2
			var turned: bool = _turn_along_wall()
			if not turned:
				chance = 0.5
			if _rng.randf() < chance:
				_enter(Act.JUMP_AWAY)
	else:
		yaw = _yaw_away_from_player()
	_step_sound()


func _tick_jump() -> void:
	if position.y <= 0.0 and _vy <= 0.0:
		position.y = 0.0
		_enter(Act.AWAY)


func _tick_wait() -> void:
	if _player_scares():
		_enter(Act.AWAY)
	elif _timer <= 0.0:
		_decide_wait_or_move()


## `aHG_decide_next_act_idx_wait_move`.
func _decide_wait_or_move() -> void:
	var pause: float = 5.0 + _rng.randf() * 5.0
	var next: Act = Act.MOVE
	var frame: int = int(Time.get_ticks_msec() / 33) % 100
	if frame > 20 or _rng.randf() < 0.5:
		next = Act.WAIT
	elif _player_distance() < SCARE:
		next = Act.WAIT
	_enter(next)
	_timer = pause


func _tick_move() -> void:
	if _player_scares():
		_enter(Act.AWAY)
		return
	if _hit_wall:
		if not _jump_flag:
			yaw += PI
		_jump_flag = true
	else:
		_jump_flag = false
	if _timer <= 0.0:
		_decide_wait_or_move()
	else:
		_step_sound()


func _tick_dead(_delta: float) -> void:
	## Blink out (`aHG_dead`) then go.
	alpha = 255.0 if (int(_timer) & 2) != 0 else 0.0
	if _timer <= 0.0:
		queue_free()


## --- movement ---------------------------------------------------------------------------

var _hit_wall: bool = false


func _move(delta: float) -> void:
	_hit_wall = false
	if act == Act.DEAD:
		return
	var v: float = speed_units * MPS
	var step := Vector3(sin(yaw), 0.0, cos(yaw)) * v * delta
	var next: Vector3 = position + step
	if _blocked(next):
		## Slide along whichever axis is still open, like the wall check.
		var x_only: Vector3 = position + Vector3(step.x, 0.0, 0.0)
		var z_only: Vector3 = position + Vector3(0.0, 0.0, step.z)
		if not _blocked(x_only):
			position.x = x_only.x
		elif not _blocked(z_only):
			position.z = z_only.z
		_hit_wall = true
	else:
		position.x = next.x
		position.z = next.z
	if act == Act.JUMP_AWAY or position.y > 0.0:
		_vy += (G_DOWN if _vy < 0.0 else G_UP) * delta
		position.y = maxf(position.y + _vy * delta, 0.0)


func _blocked(pos: Vector3) -> bool:
	var grid: WorldGrid = session.grid
	for corner: Vector3 in [Vector3(RADIUS, 0.0, 0.0), Vector3(-RADIUS, 0.0, 0.0), Vector3(0.0, 0.0, RADIUS), Vector3(0.0, 0.0, -RADIUS)]:
		var cell: Vector2i = grid.world_to_cell(pos + corner)
		if not session.room.is_inner(cell) or grid.occupant_at(cell) != &"":
			return true
	return false


## `aHG_away_bg_hitangle_check_proc`: after a wall, run along it — one of the four axes.
func _turn_along_wall() -> bool:
	var best_yaw: float = yaw
	var best: float = -INF
	var player: Node3D = _player()
	for quarter: int in 4:
		var candidate: float = quarter * PI * 0.5
		var ahead: Vector3 = position + Vector3(sin(candidate), 0.0, cos(candidate)) * (RADIUS + 0.3)
		if _blocked(ahead):
			continue
		var away: float = 0.0
		if player != null:
			away = (position + Vector3(sin(candidate), 0.0, cos(candidate)) - player.global_position).length()
		if away > best:
			best = away
			best_yaw = candidate
	if best == -INF:
		return false
	yaw = best_yaw
	_timer2 = 5.0 + _rng.randf() * 5.0
	return true


## --- the player ---------------------------------------------------------------------------


func _player() -> Node3D:
	var tree: SceneTree = get_tree()
	return tree.get_first_node_in_group("player") as Node3D if tree != null else null


func _player_distance() -> float:
	var player: Node3D = _player()
	if player == null:
		return INF
	return Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z).length()


func _player_moving() -> bool:
	var player: Node3D = _player()
	return player != null and player is CharacterBody3D and (player as CharacterBody3D).velocity.length() > 0.05


func _player_scares() -> bool:
	return _player_moving() and _player_distance() < SCARE


func _player_yaw() -> float:
	var player: Node3D = _player()
	if player == null:
		return yaw
	return atan2(global_position.x - player.global_position.x, global_position.z - player.global_position.z) + PI


func _yaw_away_from_player() -> float:
	var player: Node3D = _player()
	if player == null:
		return yaw
	return atan2(global_position.x - player.global_position.x, global_position.z - player.global_position.z)


## Trodden on by a moving player, or furniture now stands where it is (`aHG_check_dead`,
## `aMR_CheckDannaKill`).
func _should_die() -> bool:
	if position.y > 0.05:
		return false
	if _player_moving() and _player_distance() < STEP_KILL:
		return true
	var cell: Vector2i = session.grid.world_to_cell(position)
	return session.grid.occupant_at(cell) != &""


func _step_sound() -> void:
	_step_se -= get_physics_process_delta_time()
	if _step_se <= 0.0:
		_step_se = 0.25
		Audio.play_se(&"goki_move", self)


func _set_alpha(value: float) -> void:
	if _visual == null:
		return
	for node: Node in _visual.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).transparency = clampf(1.0 - value, 0.0, 1.0)
