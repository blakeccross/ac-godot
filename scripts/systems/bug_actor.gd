class_name BugActor
extends RefCounted

## One live insect. Behavioral analog of `aINS_INSECT_ACTOR` driven by the
## `aINS_PROGRAM_*` overlays. Not an autoload — `BugField` owns instances.

enum Action { IDLE, WANDER, FLEE, CAUGHT }

## `aINS_MAX_STRESS_DIST` = 3 tiles. `mFI_UNIT_BASE_SIZE_F` = 20 GX = 1 m.
const STRESS_TILES := 3.0
const STRESS_RADIUS := STRESS_TILES * FieldCatalog.GX_TO_METERS * 20.0
## `aINS_PATIENCE_STEP` = 0.5 per frame at 30 Hz → scaled to seconds.
const PATIENCE_STEP := 0.5 / 30.0
const PATIENCE_MAX := 100.0
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


class Sense:
	var player_position: Vector3 = Vector3.INF
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
			actor._beetle_sway_side = actor._rng.randi_range(0, 1)
			actor._beetle_sway_pause = actor._rng.randf_range(0.3, 0.8)
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
	if sense.has_player():
		_last_player_pos = sense.player_position
	_life -= delta
	if _life <= 0.0 and action != Action.FLEE:
		finished = true
		return
	anim_phase += delta
	_advance_pose(delta)
	_update_patience(delta, sense)
	if _patience >= PATIENCE_MAX and action != Action.FLEE:
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
	var speed: float = _cruise_speed()
	_move_forward(speed * delta)
	if _timer <= 0.0:
		yaw += _rng.randf_range(-0.8, 0.8)
		_timer = _rng.randf_range(0.6, 1.8)


func _flee(delta: float) -> void:
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


func _should_flee(sense: Sense) -> bool:
	if sense.net_swing_active and in_net_volume(
		sense.net_swing_origin,
		sense.net_swing_dir,
		Netting.SWING_LENGTH,
		Netting.SWING_RADIUS
	):
		return _patience < PATIENCE_MAX * 0.85
	if not sense.has_player():
		return false
	var dist: float = Vector2(
		sense.player_position.x - position.x, sense.player_position.z - position.z
	).length()
	if sense.player_dashing and dist < STRESS_RADIUS:
		return true
	if (sense.player_swung_tool or sense.player_swung_net) and dist < STRESS_RADIUS * 1.5:
		return true
	return false


func _update_patience(delta: float, sense: Sense) -> void:
	var stress: float = 0.0
	if sense.has_player():
		var dist: float = Vector2(
			sense.player_position.x - position.x, sense.player_position.z - position.z
		).length()
		if dist < STRESS_RADIUS:
			var t: float = 1.0 - dist / STRESS_RADIUS
			stress = t * t * 4.0
		if sense.player_dashing and dist < STRESS_RADIUS:
			stress = maxf(stress, 3.0)
	if sense.net_swing_active:
		stress = maxf(stress, 5.0)
	if stress <= 0.0:
		_patience = maxf(_patience - PATIENCE_STEP * 30.0 * delta, 0.0)
	else:
		_patience = minf(_patience + stress * PATIENCE_STEP * 30.0 * delta, PATIENCE_MAX)


func _enter(next: Action) -> void:
	action = next
	match next:
		Action.IDLE:
			_timer = _rng.randf_range(0.4, 1.2)
		Action.WANDER:
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
	if _last_player_pos != Vector3.INF:
		yaw = (
			atan2(position.x - _last_player_pos.x, position.z - _last_player_pos.z)
			+ _rng.randf_range(-FLEE_YAW_SPREAD, FLEE_YAW_SPREAD)
		)
	else:
		yaw += PI if _rng.randf() > 0.5 else 0.0
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
		_:
			_flee_speed = 2.5
			_flee_gravity = 0.3
			_flee_max_vy = 6.0
			_flee_ramp_gravity = false


func _move_forward(step: float) -> void:
	if _on_tree_trunk():
		return
	position.x += sin(yaw) * step
	position.z += cos(yaw) * step
	## Soft leash to spawn site for flying/hopping bugs.
	var drift: Vector3 = position - _home
	if Vector2(drift.x, drift.z).length() > 4.0:
		yaw = atan2(_home.x - position.x, _home.z - position.z)


func _cruise_speed() -> float:
	match bug.program if bug != null else BugData.Program.BUTTERFLY:
		BugData.Program.BUTTERFLY, BugData.Program.DRAGONFLY, BugData.Program.FIREFLY:
			return 1.6 * FieldCatalog.GX_TO_METERS
		BugData.Program.LOCUST, BugData.Program.MOLE_CRICKET:
			return 2.2 * FieldCatalog.GX_TO_METERS
		BugData.Program.WATER_SKATER:
			return 1.2 * FieldCatalog.GX_TO_METERS
		BugData.Program.BEETLE, BugData.Program.CICADA:
			return 0.4 * FieldCatalog.GX_TO_METERS
		_:
			return 0.8 * FieldCatalog.GX_TO_METERS


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


func _tick_tree_beetle(delta: float) -> void:
	## `aIKB_wait`: chase ±175.78125° (≈ ±4.2° from south) while leg poses flip.
	if _beetle_sway_pause > 0.0:
		_beetle_sway_pause = maxf(_beetle_sway_pause - delta, 0.0)
		return
	var wiggle: float = deg_to_rad(BEETLE_SWAY_DEG)
	var target: float = -TREE_FACE_YAW + (wiggle if (_beetle_sway_side & 1) == 0 else -wiggle)
	yaw = lerp_angle(yaw, target, minf(1.0, delta * 5.0))
	if absf(angle_difference(yaw, target)) < deg_to_rad(0.5):
		_beetle_sway_step += delta * 30.0
		if _beetle_sway_step >= 30.0:
			_beetle_sway_step = 0.0
			if _beetle_sway_pause <= 0.0:
				_beetle_sway_side += 1
				_beetle_sway_pause = _rng.randf_range(0.25, 0.75)


func _tick_tree_bagworm(delta: float) -> void:
	## `aIMN_calc_twist_angl` + `aIMN_position_move` while waiting on the trunk.
	_twist += delta * 30.0
	roll = sin(_twist * (TAU / 256.0)) * deg_to_rad(22.5)
	var sway: float = sin(_twist * 0.04) * FieldCatalog.GX_TO_METERS * 4.0
	position.y = _home.y + cos(pitch) * sway
	position.z = _home.z - sin(pitch) * sway
