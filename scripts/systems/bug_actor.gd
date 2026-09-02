class_name BugActor
extends RefCounted

## One live insect. Behavioral analog of `aINS_INSECT_ACTOR` driven by the
## `aINS_PROGRAM_*` overlays. Not an autoload — `BugField` owns instances.

enum Action { IDLE, WANDER, FLEE, CAUGHT }

## `aIBT_*` grasshopper / locust / cricket hop cycle (`ac_ins_batta.c`).
enum LocustPhase { WAIT, TURN, JUMP, AVOID }

## `aINS_MAX_STRESS_DIST` = 3 tiles. `mFI_UNIT_BASE_SIZE_F` = 20 GX = 1 m.
const STRESS_TILES := 3.0
## `aINS_PATIENCE_STEP` — applied once per 30 Hz sim frame (`aINS_calc_patience`).
const PATIENCE_STEP := 0.5
const PATIENCE_MAX := 100.0
## `aIKB_MAX_PATIENCE` / `aICH_check_patience`: tree programs flee above 90; butterflies at 90+.
const PATIENCE_FLEE_TREE := 90.0
const PATIENCE_FLEE_FLYING := 90.0
## `mFI_UNIT_BASE_SIZE_F` and `aINS_get_stress_sub` distance buckets.
const UNIT_GX := 20.0
const STRESS_CALC_TABLE := [0.3, 1.0, 2.0, 5.0, 10.0]
## Per-type stress radius tweak from `catch_ME_data` in `ac_insect_move.c_inc` (GX).
const CATCH_ME_GX: Array[float] = [
	0.0, 0.0, 0.0, 0.0, 10.0, 10.0, 10.0, 0.0, 10.0, 0.0, 0.0, 0.0, 0.0, 0.0, 20.0,
	-20.0, -20.0, -20.0, -20.0, -20.0, -20.0, -20.0, 0.0, 0.0, -20.0, -20.0, -20.0,
	0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
]
## Program scare radii (`aICH` / `aIKB` / `aISM` net/scoop checks).
const NET_SCARE_GX := 60.0
const NET_SCARE_TREE_GX := 70.0
const SCOOP_SCARE_GX := 30.0
## `aINS_calc_life_time` default life timer.
const LIFE_SECONDS := 3600.0 / 30.0
## Tree cling from `ac_ins_kabuto.c` / `ac_ins_semi.c` / `ac_ins_mino.c` (cedar/hardwood idx 0).
## Decomp hardwood Z is −2 GX (cedar +8). +Z is south / camera-facing here; −2 sits on the
## far side of our opaque trunks, so beetles/cicadas use a south bark stand-off (+12 GX)
## while keeping decomp yaw/height. Bagworms keep decomp −25 GX hang.
const BEETLE_HEIGHT_GX := 35.0
const BEETLE_SOUTH_Z_GX := 12.0
const BAGWORM_HEIGHT_GX := 5.0
const BAGWORM_OFFSET_Z_GX := -25.0
## `aIKB_wait` angle table ±175.78125° ≈ ±4.2° from south (−180°).
const BEETLE_SWAY_DEG := 4.21875
const TREE_FACE_YAW := PI
## Escape uses the shared insect mover at 30 Hz (`aINS_position_move` / `aIKB_avoid`).
const GAME_FPS := 30.0
## `alpha_time = 80` on avoid/let_escape; fade while `alpha_time < 24`.
const FLEE_ALPHA_FRAMES := 80.0
const FLEE_FADE_FRAMES := 24.0
const FLEE_YAW_SPREAD := deg_to_rad(60.0)
## `aIBT_chk_active_range`: 240 GX radius from spawn center.
const LOCUST_ACTIVE_RANGE_GX := 240.0
const LOCUST_AVOID_PAUSE_FRAMES := 8.0
const LOCUST_AVOID_PATIENCE_BACK := 85.0
## s16 turn jitter table from `aIBT_chg_direction`.
const LOCUST_TURN_RANGE: Array[float] = [
	4096.0, 4096.0, 8192.0, 8192.0, 8192.0, 12288.0, 12288.0, 12288.0, 12288.0,
	12288.0, 16384.0, 16384.0, 16384.0, 16384.0, 16384.0, 16384.0,
]
const LOCUST_TYPE_LONG := 13
const LOCUST_TYPE_MIGRATORY := 14


class Sense:
	var player_position: Vector3 = Vector3.INF
	## Planar speed as GX per 30 Hz frame (`actor.speed` units). Fallback when position delta is zero.
	var player_move_gx: float = 0.0
	var player_dashing: bool = false
	var player_swung_tool: bool = false
	var player_swung_net: bool = false
	var net_swing_origin: Vector3 = Vector3.INF
	var net_swing_dir: Vector3 = Vector3.ZERO
	var net_swing_active: bool = false
	var player_action_cell: Vector2i = Vector2i(-1, -1)

	func has_player() -> bool:
		return player_position != Vector3.INF


var bug: BugData = null
var habitat: BugData.Habitat = BugData.Habitat.FLYING
var position: Vector3 = Vector3.ZERO
var yaw: float = 0.0
var pitch: float = 0.0
var height: float = 0.0
var action: Action = Action.IDLE
var finished: bool = false
var caught: bool = false
var anim_phase: float = 0.0
var roll: float = 0.0
## Draw alpha 0–1 (`aINS_calc_alpha_time` / `alpha0`).
var alpha: float = 1.0

var _patience: float = 0.0
var _life: float = LIFE_SECONDS
var _timer: float = 0.0
var _home: Vector3 = Vector3.ZERO
var _rng: RandomNumberGenerator = null
var _pose_pattern: Array[int] = [0]
var _pose_frame: int = 0
var _pose_tick: float = 0.0
var _beetle_sway_side: int = 0
var _beetle_sway_pause: float = 0.0
var _beetle_sway_step: float = 0.0
var _tree_center: Vector3 = Vector3.ZERO
var _twist: float = 0.0
var _clinging: bool = false
var _vel_y: float = 0.0
var _flee_speed: float = 0.0
var _flee_gravity: float = 0.0
var _flee_max_vy: float = 0.0
var _flee_ramp_gravity: bool = false
var _flee_anime: float = 0.0
var _alpha_time: float = 0.0
var _last_player_pos: Vector3 = Vector3.INF
var _ground_y: float = 0.0
var _locust_phase: LocustPhase = LocustPhase.WAIT
var _locust_dir_attempts: int = 0
var _locust_hop_speed: float = 0.0
var _locust_hop_gravity: float = 0.7
var _locust_airborne: bool = false


static func create(
	p_bug: BugData,
	p_habitat: BugData.Habitat,
	p_position: Vector3,
	rng: RandomNumberGenerator
) -> BugActor:
	var actor := BugActor.new()
	actor.bug = p_bug
	actor.habitat = p_habitat
	actor.position = p_position
	actor._home = p_position
	actor._rng = rng if rng != null else RandomNumberGenerator.new()
	actor.height = _flight_height(p_bug, p_habitat)
	if p_bug != null:
		actor._pose_pattern = BugData.pose_pattern(p_bug.model_flap)
		actor._pose_frame = 0
		actor._pose_tick = 0.0
	if p_habitat == BugData.Habitat.TREE:
		_configure_tree_cling(actor)
		actor.height = 0.0
	elif p_bug != null and p_bug.program == BugData.Program.LOCUST:
		actor._ground_y = p_position.y
		actor._begin_locust_wait()
	actor._enter(Action.WANDER)
	return actor


static func _configure_tree_cling(actor: BugActor) -> void:
	## Fixed south face (`ac_ins_kabuto` / `semi` / `mino`): yaw 180° / −180°, decomp height.
	## Beetles/cicadas use south bark stand-off so opaque trunks do not hide them.
	actor._clinging = true
	actor._tree_center = actor.position
	var gx: float = FieldCatalog.GX_TO_METERS
	match actor.bug.program if actor.bug != null else BugData.Program.BEETLE:
		BugData.Program.BAGWORM:
			actor.pitch = deg_to_rad(47.8125)
			actor.yaw = TREE_FACE_YAW
			actor.position.y = actor._tree_center.y + BAGWORM_HEIGHT_GX * gx
			actor.position.z = actor._tree_center.z + BAGWORM_OFFSET_Z_GX * gx
		BugData.Program.BEETLE:
			actor.pitch = PI * 0.5
			actor.yaw = -TREE_FACE_YAW
			actor.position.y = actor._tree_center.y + BEETLE_HEIGHT_GX * gx
			actor.position.z = actor._tree_center.z + BEETLE_SOUTH_Z_GX * gx
			actor._beetle_sway_side = 0
			actor._beetle_sway_pause = 0.0
			actor._beetle_sway_step = 30.0
		_:
			actor.pitch = PI * 0.5
			actor.yaw = TREE_FACE_YAW
			actor.position.y = actor._tree_center.y + BEETLE_HEIGHT_GX * gx
			actor.position.z = actor._tree_center.z + BEETLE_SOUTH_Z_GX * gx
	actor._home = actor.position


func pose_index() -> int:
	if bug == null:
		return 0
	## `aIKB_anime_proc` / `aISM_anime_proc` run during avoid — flap even when idle is still.
	if action == Action.FLEE and _flees_with_anime():
		return int(_flee_anime) & 1
	if bug.model_flap == 0:
		if bug.program == BugData.Program.BEETLE and _on_tree_trunk():
			return _beetle_sway_side & 1
		return 0
	if _pose_pattern.is_empty():
		return 0
	return _pose_pattern[_pose_frame]


func tick(delta: float, sense: Sense) -> void:
	if finished:
		return
	_life -= delta
	if _life <= 0.0 and action != Action.FLEE:
		finished = true
		return
	anim_phase += delta
	_advance_pose(delta)
	_update_patience(delta, sense)
	_apply_program_scares(sense)
	if _patience_triggers_flee() and action != Action.FLEE:
		if _uses_locust_hops():
			if _locust_phase != LocustPhase.AVOID:
				_begin_locust_avoid(sense)
		else:
			_enter(Action.FLEE)
	match action:
		Action.IDLE:
			_idle(delta, sense)
		Action.WANDER:
			_wander(delta, sense)
		Action.FLEE:
			_flee(delta)
		Action.CAUGHT:
			pass
	_track_player_position(sense)


func catch() -> void:
	if finished:
		return
	action = Action.CAUGHT
	caught = true
	finished = true


func release() -> void:
	if finished:
		return
	_patience = PATIENCE_MAX
	_enter(Action.FLEE)


func in_net_volume(origin: Vector3, direction: Vector3, length: float, radius: float) -> bool:
	## `Player_actor_Item_CheckLocalCapture_forNet`: capsule in front of the swing.
	var to: Vector3 = position - origin
	var along: float = to.dot(direction)
	if along < 0.0 or along > length:
		return false
	var closest: Vector3 = origin + direction * along
	return Vector2(closest.x - position.x, closest.z - position.z).length() <= radius


func _idle(delta: float, sense: Sense) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_enter(Action.WANDER)
	if _should_flee(sense):
		_enter(Action.FLEE)


func _wander(delta: float, sense: Sense) -> void:
	if _uses_locust_hops():
		_tick_locust_wander(delta, sense)
		return
	if _should_flee(sense):
		_enter(Action.FLEE)
		return
	if _on_tree_trunk():
		if bug.program == BugData.Program.BEETLE:
			_tick_tree_beetle(delta)
		elif bug.program == BugData.Program.BAGWORM:
			_tick_tree_bagworm(delta)
		_timer -= delta
		if _timer <= 0.0:
			_timer = _rng.randf_range(0.8, 2.0)
		return
	_timer -= delta
	var frames: float = GAME_FPS * delta
	_move_forward_gx(_cruise_speed_gx() * frames)
	if _timer <= 0.0:
		yaw += _rng.randf_range(-0.8, 0.8)
		_timer = _rng.randf_range(0.6, 1.8)


func _flee(delta: float) -> void:
	if _uses_locust_hops():
		_tick_locust_escape(delta)
		return
	## `aINS_position_move` + per-program avoid: horizontal speed, optional Y chase, alpha.
	var frames: float = GAME_FPS * delta
	var gx: float = FieldCatalog.GX_TO_METERS
	position.x += sin(yaw) * _flee_speed * gx * frames
	position.z += cos(yaw) * _flee_speed * gx * frames
	if not is_zero_approx(_flee_max_vy) or not is_zero_approx(_flee_gravity):
		var steps: int = maxi(1, ceili(frames))
		var sub: float = frames / float(steps)
		for _i: int in steps:
			if _flee_ramp_gravity:
				_flee_gravity = minf(_flee_gravity * pow(1.1, sub), absf(_flee_max_vy))
			var rate: float = _flee_gravity * 0.5 * sub
			if _vel_y < _flee_max_vy:
				_vel_y = minf(_vel_y + rate, _flee_max_vy)
			elif _vel_y > _flee_max_vy:
				_vel_y = maxf(_vel_y - rate, _flee_max_vy)
		position.y += _vel_y * gx * frames
	if _flees_with_anime():
		_flee_anime += 0.5 * frames
		while _flee_anime >= 2.0:
			_flee_anime -= 2.0
	_alpha_time -= frames
	if _alpha_time <= 0.0:
		alpha = 0.0
		finished = true
		return
	if _alpha_time < FLEE_FADE_FRAMES:
		var fade_frames: float = FLEE_FADE_FRAMES - _alpha_time
		alpha = clampf(1.0 - fade_frames * (11.0 / 255.0), 0.0, 1.0)
		if alpha <= 0.0:
			finished = true
	else:
		alpha = 1.0


func _should_flee(_sense: Sense) -> bool:
	return _patience_triggers_flee()


func _patience_triggers_flee() -> bool:
	if bug != null and bug.program in [
		BugData.Program.BUTTERFLY,
		BugData.Program.DRAGONFLY,
		BugData.Program.FIREFLY,
		BugData.Program.LOCUST,
	]:
		return _patience >= PATIENCE_FLEE_FLYING
	return _patience > PATIENCE_FLEE_TREE


func _catch_me_gx() -> float:
	if bug == null or bug.type_index < 0 or bug.type_index >= CATCH_ME_GX.size():
		return 0.0
	return CATCH_ME_GX[bug.type_index]


func _stress_radius_gx() -> float:
	return STRESS_TILES * UNIT_GX + _catch_me_gx()


func _player_move_gx(sense: Sense, delta: float) -> float:
	if not sense.has_player():
		return 0.0
	var move_gx: float = 0.0
	if _last_player_pos != Vector3.INF and delta > 0.0:
		var dx: float = sense.player_position.x - _last_player_pos.x
		var dz: float = sense.player_position.z - _last_player_pos.z
		var observed: float = Vector2(dx, dz).length() / FieldCatalog.GX_TO_METERS
		var sim_frames: float = GAME_FPS * delta
		if sim_frames > 0.0:
			move_gx = observed / sim_frames
	if move_gx <= 0.0 and sense.player_move_gx > 0.0:
		move_gx = sense.player_move_gx
	return move_gx


func _calc_stress(sense: Sense, delta: float) -> float:
	if not sense.has_player():
		return 0.0
	var dist_gx: float = Vector2(
		sense.player_position.x - position.x, sense.player_position.z - position.z
	).length() / FieldCatalog.GX_TO_METERS
	var min_dist_gx: float = _stress_radius_gx()
	if dist_gx >= min_dist_gx:
		return 0.0
	var tmp0: float = maxf(dist_gx - UNIT_GX, 0.0)
	var idx: int = int((min_dist_gx - UNIT_GX - tmp0) / UNIT_GX)
	idx = clampi(idx, 0, STRESS_CALC_TABLE.size() - 1)
	return _player_move_gx(sense, delta) * STRESS_CALC_TABLE[idx]


func _track_player_position(sense: Sense) -> void:
	if sense.has_player():
		_last_player_pos = sense.player_position


func _apply_program_scares(sense: Sense) -> void:
	if sense.net_swing_active and sense.net_swing_origin != Vector3.INF:
		var net_dist_gx: float = Vector2(
			sense.net_swing_origin.x - position.x, sense.net_swing_origin.z - position.z
		).length() / FieldCatalog.GX_TO_METERS
		if net_dist_gx < _net_scare_dist_gx():
			_patience = PATIENCE_MAX
	if sense.player_swung_tool and _uses_scoop_scare():
		var dist_gx: float = Vector2(
			sense.player_position.x - position.x, sense.player_position.z - position.z
		).length() / FieldCatalog.GX_TO_METERS
		if dist_gx < SCOOP_SCARE_GX:
			_patience = PATIENCE_MAX


func _net_scare_dist_gx() -> float:
	match bug.program if bug != null else BugData.Program.BUTTERFLY:
		BugData.Program.BEETLE, BugData.Program.CICADA, BugData.Program.LADYBUG, BugData.Program.COCKROACH:
			return NET_SCARE_TREE_GX
		_:
			return NET_SCARE_GX


func _uses_scoop_scare() -> bool:
	if bug == null:
		return false
	return bug.program in [BugData.Program.BEETLE, BugData.Program.CICADA]


func _update_patience(delta: float, sense: Sense) -> void:
	var stress: float = _calc_stress(sense, delta)
	var step: float = PATIENCE_STEP * GAME_FPS * delta
	if is_zero_approx(stress):
		_patience = maxf(_patience - step, 0.0)
	else:
		_patience = minf(_patience + stress * step, PATIENCE_MAX)


func _enter(next: Action) -> void:
	action = next
	match next:
		Action.IDLE:
			_timer = _rng.randf_range(0.4, 1.2)
		Action.WANDER:
			if _uses_locust_hops():
				_begin_locust_wait()
			else:
				_timer = _rng.randf_range(0.8, 2.0)
				if not _on_tree_trunk():
					yaw = _rng.randf_range(-PI, PI)
		Action.FLEE:
			_begin_flee()
		Action.CAUGHT:
			_timer = 0.0


func _begin_flee() -> void:
	## `aIKB_avoid_init` / `aISM_avoid_init` / `aIMN_let_escape_init`.
	_clinging = false
	pitch = 0.0
	roll = 0.0
	height = 0.0
	_vel_y = 0.0
	_flee_anime = 0.0
	_alpha_time = FLEE_ALPHA_FRAMES
	alpha = 1.0
	_life = 0.0
	_configure_flee_yaw()
	match bug.program if bug != null else BugData.Program.BUTTERFLY:
		BugData.Program.BAGWORM:
			## Fall off the silk: gravity 2 → max_vy −20, crawl speed 0.75.
			_flee_speed = 0.75
			_flee_gravity = 2.0
			_flee_max_vy = -20.0
			_flee_ramp_gravity = false
		BugData.Program.BEETLE, BugData.Program.CICADA:
			## Fly up and away: speed 4, gravity 0.06×1.1/frame → 12.
			_flee_speed = 4.0
			_flee_gravity = 0.06
			_flee_max_vy = 12.0
			_flee_ramp_gravity = true
		BugData.Program.BUTTERFLY, BugData.Program.DRAGONFLY, BugData.Program.FIREFLY:
			## Horizontal dash (`aICH_let_escape` speed ~1.5–3); no Y chase in mover.
			_flee_speed = 3.0
			_flee_gravity = 0.0
			_flee_max_vy = 0.0
			_flee_ramp_gravity = false
		BugData.Program.LOCUST:
			## `aIBT_let_escape_init`: hop away while fading out.
			_locust_phase = LocustPhase.JUMP
			_locust_airborne = true
			_locust_hop_speed = 5.0
			_vel_y = 3.0
			_locust_hop_gravity = 0.2
			_flee_max_vy = -20.0
			_flee_speed = 0.0
			_flee_gravity = 0.0
			_flee_ramp_gravity = false
		_:
			_flee_speed = 2.5
			_flee_gravity = 0.3
			_flee_max_vy = 6.0
			_flee_ramp_gravity = false


func _move_forward_gx(step_gx: float) -> void:
	if _on_tree_trunk():
		return
	var gx: float = FieldCatalog.GX_TO_METERS
	position.x += sin(yaw) * step_gx * gx
	position.z += cos(yaw) * step_gx * gx
	## Soft leash to spawn site for flying/hopping bugs.
	var drift: Vector3 = position - _home
	if Vector2(drift.x, drift.z).length() > 4.0:
		yaw = atan2(_home.x - position.x, _home.z - position.z)


func _cruise_speed_gx() -> float:
	## `target_speed` from decomp wander actions (`aICH_fly_init`, `aIBT_*`, etc.).
	match bug.program if bug != null else BugData.Program.BUTTERFLY:
		BugData.Program.BUTTERFLY, BugData.Program.DRAGONFLY, BugData.Program.FIREFLY:
			return 2.0
		BugData.Program.MOLE_CRICKET:
			return 5.0
		BugData.Program.WATER_SKATER:
			return 0.8
		BugData.Program.LADYBUG:
			return 0.3
		BugData.Program.MANTIS:
			return 1.5
		BugData.Program.BEETLE, BugData.Program.CICADA, BugData.Program.BAGWORM:
			return 0.0
		BugData.Program.PILL_BUG, BugData.Program.COCKROACH:
			return 0.4
		_:
			return 1.0


static func _flight_height(p_bug: BugData, p_habitat: BugData.Habitat) -> float:
	match p_bug.program if p_bug != null else BugData.Program.BUTTERFLY:
		BugData.Program.BUTTERFLY, BugData.Program.DRAGONFLY, BugData.Program.FIREFLY, BugData.Program.MANTIS:
			return 1.2
		BugData.Program.WATER_SKATER:
			return 0.05
		BugData.Program.BEETLE, BugData.Program.CICADA, BugData.Program.LADYBUG:
			return 0.8 if p_habitat == BugData.Habitat.TREE else 0.3
		_:
			return 0.35


func _on_tree_trunk() -> bool:
	return _clinging


func _flees_with_anime() -> bool:
	if bug == null:
		return false
	return bug.program in [
		BugData.Program.BEETLE,
		BugData.Program.CICADA,
		BugData.Program.BAGWORM,
	]


func _clings_to_tree() -> bool:
	return (
		_on_tree_trunk()
		and bug != null
		and bug.program in [BugData.Program.BEETLE, BugData.Program.BAGWORM]
	)


func _advance_pose(delta: float) -> void:
	if bug == null or bug.model_flap <= 0 or _pose_pattern.size() <= 1:
		return
	_pose_tick += delta
	var step: float = 1.0 / BugData.POSE_FLAP_HZ
	while _pose_tick >= step:
		_pose_tick -= step
		_pose_frame = (_pose_frame + 1) % _pose_pattern.size()


func _configure_flee_yaw() -> void:
	## `aIKB_avoid_init` / `aISM_avoid_init` / `aICH_let_escape_init`: away from player ± spread.
	if _last_player_pos == Vector3.INF:
		yaw += PI if _rng.randf() > 0.5 else 0.0
		return
	yaw = atan2(position.x - _last_player_pos.x, position.z - _last_player_pos.z)
	yaw += _rng.randf_range(-FLEE_YAW_SPREAD, FLEE_YAW_SPREAD)


func _tick_tree_beetle(delta: float) -> void:
	## `aIKB_wait`: chase ±175.78125° (≈ ±4.2° from south) while leg poses flip.
	var frames: float = GAME_FPS * delta
	if _beetle_sway_pause > 0.0:
		_beetle_sway_pause = maxf(_beetle_sway_pause - frames, 0.0)
		return
	var wiggle: float = deg_to_rad(BEETLE_SWAY_DEG)
	var target: float = -TREE_FACE_YAW + (wiggle if (_beetle_sway_side & 1) == 0 else -wiggle)
	yaw = lerp_angle(yaw, target, minf(1.0, frames / 6.0))
	if absf(angle_difference(yaw, target)) < deg_to_rad(0.5):
		if _beetle_sway_step <= 0.0:
			if (_beetle_sway_side & 1) == 0:
				_beetle_sway_side = 1
			else:
				_beetle_sway_side = 0
				_beetle_sway_pause = _rng.randf_range(20.0, 40.0)
		else:
			_beetle_sway_step = maxf(_beetle_sway_step - frames, 0.0)
	else:
		_beetle_sway_step = 30.0


func _tick_tree_bagworm(delta: float) -> void:
	## `aIMN_calc_twist_angl` + `aIMN_position_move` while waiting on the trunk.
	_twist += delta * 30.0
	roll = sin(_twist * (TAU / 256.0)) * deg_to_rad(22.5)
	var sway: float = sin(_twist * 0.04) * FieldCatalog.GX_TO_METERS * 4.0
	position.y = _home.y + cos(pitch) * sway
	position.z = _home.z - sin(pitch) * sway


func _uses_locust_hops() -> bool:
	return bug != null and bug.program == BugData.Program.LOCUST


func _is_migratory_locust() -> bool:
	return bug != null and bug.type_index == LOCUST_TYPE_MIGRATORY


func _is_long_or_migratory_locust() -> bool:
	return bug != null and bug.type_index in [LOCUST_TYPE_LONG, LOCUST_TYPE_MIGRATORY]


func _locust_in_active_range() -> bool:
	var drift_gx: float = Vector2(position.x - _home.x, position.z - _home.z).length() / FieldCatalog.GX_TO_METERS
	return drift_gx < LOCUST_ACTIVE_RANGE_GX


func _begin_locust_wait() -> void:
	_locust_phase = LocustPhase.WAIT
	_locust_airborne = false
	_vel_y = 0.0
	position.y = _ground_y
	if _locust_in_active_range():
		_timer = 2.0 * (120.0 + float(_rng.randi_range(0, 239))) / GAME_FPS
	else:
		_timer = 60.0 / GAME_FPS


func _begin_locust_turn() -> void:
	_locust_phase = LocustPhase.TURN
	_pick_locust_wander_yaw()
	_begin_locust_wait()


func _pick_locust_wander_yaw() -> void:
	var idx: int = clampi(_locust_dir_attempts, 0, LOCUST_TURN_RANGE.size() - 1)
	var spread: float = LOCUST_TURN_RANGE[idx] * TAU / 65536.0
	yaw = wrapf(yaw + PI + spread * _rng.randf_range(-1.0, 1.0), -PI, PI)
	_locust_dir_attempts += 1


func _begin_locust_jump(avoid: bool) -> void:
	_locust_phase = LocustPhase.AVOID if avoid else LocustPhase.JUMP
	_locust_airborne = true
	if avoid and _is_migratory_locust():
		_locust_hop_speed = 7.5
		_vel_y = 9.0
		_locust_hop_gravity = 0.6
	elif avoid:
		_locust_hop_speed = 5.0
		_vel_y = 3.0
		_locust_hop_gravity = 0.3
	else:
		_locust_hop_speed = 5.5
		_vel_y = 4.0
		_locust_hop_gravity = 0.7
	_flee_max_vy = -20.0


func _begin_locust_avoid(sense: Sense) -> void:
	_locust_phase = LocustPhase.AVOID
	_locust_airborne = false
	_vel_y = 0.0
	position.y = _ground_y
	_timer = 0.0
	if sense.has_player():
		yaw = atan2(position.x - sense.player_position.x, position.z - sense.player_position.z)
		yaw += _rng.randf_range(-PI * 0.25, PI * 0.25)


func _tick_locust_wander(delta: float, sense: Sense) -> void:
	if _locust_phase == LocustPhase.AVOID:
		_tick_locust_avoid(delta, sense)
		return
	if _locust_airborne:
		_locust_integrate(delta)
		if _locust_landed():
			_locust_airborne = false
			_vel_y = 0.0
			position.y = _ground_y
			_begin_locust_turn()
		return
	_timer -= delta
	if _timer > 0.0:
		return
	var pick_jump: bool = not _locust_in_active_range()
	if not pick_jump:
		if _is_long_or_migratory_locust():
			pick_jump = _rng.randf() > 0.1
		else:
			pick_jump = _rng.randf() < 0.1
	if pick_jump:
		_begin_locust_jump(false)
	else:
		_begin_locust_turn()


func _tick_locust_avoid(delta: float, sense: Sense) -> void:
	if _locust_airborne:
		_locust_integrate(delta)
		if _locust_landed():
			_locust_airborne = false
			_vel_y = 0.0
			position.y = _ground_y
			_timer = LOCUST_AVOID_PAUSE_FRAMES / GAME_FPS
		return
	_timer -= delta
	if _timer > 0.0:
		return
	if _patience < LOCUST_AVOID_PATIENCE_BACK:
		_begin_locust_turn()
		return
	if sense.has_player():
		yaw = atan2(position.x - sense.player_position.x, position.z - sense.player_position.z)
		yaw += _rng.randf_range(-PI * 0.25, PI * 0.25)
	_begin_locust_jump(true)
	_timer = LOCUST_AVOID_PAUSE_FRAMES / GAME_FPS


func _tick_locust_escape(delta: float) -> void:
	var frames: float = GAME_FPS * delta
	if _locust_airborne:
		_locust_integrate(delta)
		if _locust_landed():
			_locust_airborne = false
			_vel_y = 0.0
			position.y = _ground_y
			_timer = LOCUST_AVOID_PAUSE_FRAMES / GAME_FPS
	elif _timer > 0.0:
		_timer -= delta
	else:
		_begin_locust_jump(true)
		_timer = LOCUST_AVOID_PAUSE_FRAMES / GAME_FPS
	_alpha_time -= frames
	if _alpha_time <= 0.0:
		alpha = 0.0
		finished = true
		return
	if _alpha_time < FLEE_FADE_FRAMES:
		var fade_frames: float = FLEE_FADE_FRAMES - _alpha_time
		alpha = clampf(1.0 - fade_frames * (11.0 / 255.0), 0.0, 1.0)
		if alpha <= 0.0:
			finished = true
	else:
		alpha = 1.0


func _locust_integrate(delta: float) -> void:
	var frames: float = GAME_FPS * delta
	var gx: float = FieldCatalog.GX_TO_METERS
	position.x += sin(yaw) * _locust_hop_speed * gx * frames
	position.z += cos(yaw) * _locust_hop_speed * gx * frames
	var steps: int = maxi(1, ceili(frames))
	var sub: float = frames / float(steps)
	for _i: int in steps:
		var rate: float = _locust_hop_gravity * 0.5 * sub
		if _vel_y > _flee_max_vy:
			_vel_y = maxf(_vel_y - rate, _flee_max_vy)
	position.y += _vel_y * gx * frames


func _locust_landed() -> bool:
	return position.y <= _ground_y + 0.001 and _vel_y <= 0.0
