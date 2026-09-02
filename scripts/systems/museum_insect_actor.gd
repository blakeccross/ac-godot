class_name MuseumInsectActor
extends RefCounted

## One donated insect in the museum wing (`PRIV_INSECT` / `minsect_*`).
## Anchors and active/relax windows come from `ac_museum_insect`; motion is a lighter
## museum-idle version of field `BugActor` programs so wings still flap on schedule.

const GAME_FPS := 30.0
const BEETLE_HEIGHT_GX := 35.0

var bug: BugData = null
var type_index: int = -1
var position: Vector3 = Vector3.ZERO
var yaw: float = 0.0
var pitch: float = 0.0
var height: float = 0.0
var active: bool = true
var anim_phase: float = 0.0

var _home: Vector3 = Vector3.ZERO
var _rng: RandomNumberGenerator = null
var _pose_pattern: Array[int] = [0]
var _pose_frame: int = 0
var _pose_tick: float = 0.0
var _timer: float = 0.0
var _draw_scale: float = 0.01
var _program: BugData.Program = BugData.Program.BUTTERFLY


static func create(p_bug: BugData, grid: WorldGrid, rng: RandomNumberGenerator) -> MuseumInsectActor:
	if p_bug == null:
		return null
	var actor := MuseumInsectActor.new()
	actor.bug = p_bug
	actor.type_index = p_bug.type_index
	actor._rng = rng if rng != null else RandomNumberGenerator.new()
	actor._program = p_bug.program
	actor._pose_pattern = BugData.pose_pattern(p_bug.model_flap)
	if actor.type_index >= 0 and actor.type_index < MuseumDisplay.INSECT_SCALES.size():
		actor._draw_scale = MuseumDisplay.INSECT_SCALES[actor.type_index]
	actor._home = MuseumDisplay.gx_to_world(grid, _anchor_gx(p_bug))
	actor.position = actor._home
	actor.height = _start_height(p_bug)
	actor.yaw = actor._rng.randf() * TAU
	actor.active = MuseumDisplay.insect_is_active(actor.type_index, Clock.hour, Clock.minute)
	actor._timer = actor._rng.randf_range(0.8, 2.5)
	return actor


static func _anchor_gx(bug: BugData) -> Vector3:
	match bug.program:
		BugData.Program.BUTTERFLY, BugData.Program.LADYBUG, BugData.Program.MANTIS:
			if bug.id == &"purple_butterfly":
				return MuseumDisplay.INSECT_OHMURASAKI_TREE
			var flowers: Array[Vector3] = MuseumDisplay.INSECT_FLOWER_POS
			return flowers[abs(bug.type_index) % flowers.size()]
		BugData.Program.CICADA, BugData.Program.BEETLE, BugData.Program.BAGWORM:
			var trees: Array[Vector3] = MuseumDisplay.INSECT_TREE_POS
			return trees[abs(bug.type_index) % trees.size()]
		BugData.Program.DRAGONFLY:
			var rocks: Array[Vector3] = MuseumDisplay.INSECT_ROCK_POS
			return rocks[abs(bug.type_index) % rocks.size()] + Vector3(0.0, 40.0, 0.0)
		BugData.Program.WATER_SKATER:
			return MuseumDisplay.INSECT_AMENBO_CENTER
		BugData.Program.MOLE_CRICKET:
			return MuseumDisplay.INSECT_OKERA_BASE
		BugData.Program.FIREFLY:
			return MuseumDisplay.INSECT_GENJI_BASE
		BugData.Program.LOCUST, BugData.Program.COCKROACH, BugData.Program.PILL_BUG:
			var ground: Array[Vector3] = MuseumDisplay.INSECT_ROCK_POS
			return ground[abs(bug.type_index) % ground.size()] + Vector3(20.0, 20.0, 0.0)
		_:
			var fallback: Array[Vector3] = MuseumDisplay.INSECT_FLOWER_POS
			return fallback[abs(bug.type_index) % fallback.size()]


static func _start_height(bug: BugData) -> float:
	match bug.program:
		BugData.Program.BEETLE, BugData.Program.CICADA:
			return BEETLE_HEIGHT_GX * FieldCatalog.GX_TO_METERS
		BugData.Program.BAGWORM:
			return 5.0 * FieldCatalog.GX_TO_METERS
		BugData.Program.BUTTERFLY, BugData.Program.DRAGONFLY, BugData.Program.FIREFLY:
			return 0.4
		BugData.Program.WATER_SKATER:
			return 0.05
		_:
			return 0.0


func render_scale() -> float:
	## `minsect_scale_tbl` → same conversion as field insects.
	return _draw_scale / FieldCatalog.PIPELINE_SCALE * FieldCatalog.GX_TO_METERS


func pose_index() -> int:
	if _pose_pattern.is_empty():
		return 0
	return _pose_pattern[_pose_frame % _pose_pattern.size()]


func tick(delta: float) -> void:
	if bug == null:
		return
	active = MuseumDisplay.insect_is_active(type_index, Clock.hour, Clock.minute)
	_tick_pose(delta)
	if not active:
		## `get_now_mind_flag` slows timers ×10 while "asleep".
		_timer -= delta * 0.1
		anim_phase = 0.0
		return
	_timer -= delta
	anim_phase += delta
	match _program:
		BugData.Program.BUTTERFLY, BugData.Program.DRAGONFLY, BugData.Program.FIREFLY:
			_fly_orbit(delta)
		BugData.Program.WATER_SKATER:
			_skate(delta)
		BugData.Program.LOCUST, BugData.Program.COCKROACH, BugData.Program.PILL_BUG:
			_ground_wander(delta)
		BugData.Program.BEETLE, BugData.Program.CICADA, BugData.Program.BAGWORM:
			_tree_sway(delta)
		_:
			_idle_bob(delta)
	if _timer <= 0.0:
		_timer = _rng.randf_range(1.2, 3.5)
		yaw = wrapf(yaw + _rng.randf_range(-0.8, 0.8), -PI, PI)


func _tick_pose(delta: float) -> void:
	if _pose_pattern.size() <= 1:
		return
	## Still flap slowly while relaxed so cases are not frozen silhouettes.
	var rate: float = 1.0 if active else 0.25
	_pose_tick += delta * rate
	var step: float = 1.0 / BugData.POSE_FLAP_HZ
	while _pose_tick >= step:
		_pose_tick -= step
		_pose_frame = (_pose_frame + 1) % _pose_pattern.size()


func _fly_orbit(delta: float) -> void:
	var radius: float = 0.35 if _program == BugData.Program.FIREFLY else 0.55
	var angle: float = anim_phase * (1.4 if active else 0.3)
	position.x = _home.x + cos(angle + yaw) * radius
	position.z = _home.z + sin(angle + yaw) * radius
	position.y = _home.y + height + sin(anim_phase * 2.2) * 0.08
	yaw = angle + PI * 0.5


func _skate(delta: float) -> void:
	var box := Vector2(25.0, 18.0) * FieldCatalog.GX_TO_METERS
	position += Vector3(sin(yaw), 0.0, cos(yaw)) * 0.45 * delta
	if absf(position.x - _home.x) > box.x or absf(position.z - _home.z) > box.y:
		yaw = wrapf(yaw + PI * 0.5 + _rng.randf_range(-0.3, 0.3), -PI, PI)
		position.x = clampf(position.x, _home.x - box.x, _home.x + box.x)
		position.z = clampf(position.z, _home.z - box.y, _home.z + box.y)
	position.y = _home.y + height


func _ground_wander(delta: float) -> void:
	position += Vector3(sin(yaw), 0.0, cos(yaw)) * 0.35 * delta
	var d: Vector3 = position - _home
	d.y = 0.0
	if d.length() > 1.2:
		yaw = atan2(-d.x, -d.z) + _rng.randf_range(-0.4, 0.4)
	position.y = _home.y


func _tree_sway(delta: float) -> void:
	yaw = PI + sin(anim_phase * 0.7) * deg_to_rad(BugActor.BEETLE_SWAY_DEG)
	position = _home
	position.y = _home.y + height
	var _unused: float = delta


func _idle_bob(delta: float) -> void:
	position = _home
	position.y = _home.y + height + sin(anim_phase * 1.5) * 0.03
	var _unused: float = delta
