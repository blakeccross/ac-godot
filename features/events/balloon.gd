class_name Balloon
extends Node3D

## A balloon carrying a present across town (`ac_fuusen`, skeleton `act_balloon`, the
## present `present_DL_*` hanging below). Born just outside the map on the wind's side
## (`aFSN_birth_init`: eight edge spots picked by wind direction, spread along the edge), it
## drifts downwind at 1–1.5 GX a frame, bobbing 110 GX over the ground and rising over walls.
## A grown, fruitless tree ahead (±2500 binangle, 80 GX out) pulls it in once; inside a tree
## unit it snags at the crown (`aFSN_wood_stop`). A full shake lets it go and the present
## drops like fruit; a bump wobbles it. After 10 minutes snagged, 2000 frames drifting to
## the map edge, or at the station, it escapes upward with its present.
##
## Positions are kept in decomp world units (GX, the whole map including the border acres);
## time is seconds. Its per-frame numbers (30 fps) are converted where they are written.

enum Action { BIRTH, MOVING, WOOD_STOP, ESCAPE }

const FRAME_HZ := DecompTime.FRAME_HZ
## `aFSN_ESCAPE_TIMER` (1554 frames), the drifting grace period (2000), the snag time (18000
## frames: ten minutes).
const ESCAPE_SEC := 1554.0 / FRAME_HZ
const DRIFT_SEC := 2000.0 / FRAME_HZ
const SNAG_SEC := 18000.0 / FRAME_HZ
## `timer = 10`: frames before it starts moving.
const HOLD_SEC := 10.0 / FRAME_HZ
## A bump wobbles it for 12 frames, flipping its tilt every 4.
const WOBBLE_SEC := 12.0 / FRAME_HZ
## Lengths in metres, from the decomp's GX.
const GX := FieldCatalog.GX_TO_METERS
const HEIGHT := 110.0 * GX
const HEIGHT_MAX := 300.0 * GX
const BIRTH_HEIGHT := 200.0 * GX
const LEAVE_HEIGHT := 500.0 * GX
## The bob turns 250 binangle a frame.
const BOB_RATE := 250.0 * FRAME_HZ
const BOB := 10.0 * GX
## `add_calc(…, 1 - sqrt(0.7), 0.5, 0)` a frame, as a half-life and a top speed (0.5 GX a frame).
static var EASE_HALF_LIFE: float = Motion.half_life_from_fraction(0.16333997, FRAME_HZ)
const EASE_MAX_SPEED := 0.5 * GX * FRAME_HZ
## Over a wall it climbs 0.05 GX a frame; back in the open it sinks 0.005.
const CLIMB_SPEED := 0.05 * GX * FRAME_HZ
const SINK_SPEED := 0.005 * GX * FRAME_HZ
## Escaping, it rises faster by 0.5 GX a frame each frame, up to 5 GX a frame.
const RISE_ACCEL := 0.5 * GX * FRAME_HZ * FRAME_HZ
const RISE_MAX := 5.0 * GX * FRAME_HZ
## `Actor_position_moveF` downwind: 1 GX a frame, half a GX more at full wind.
const DRIFT_SPEED := 1.0 * GX * FRAME_HZ
## How near a snaggable crown it has to drift (22 GX for a cedar, 15 for others, within 15
## up or down), and how close it has to come to sit still on it.
const SNAG_REACH_CEDAR := 22.0 * GX
const SNAG_REACH := 15.0 * GX
const SNAG_HEIGHT := 15.0 * GX
const PERCH_SETTLE := 2.0 * GX
## `mCoBG_BgCheckControll(…, 12, …)`: a wall is the ground 12 GX ahead stepping up 20.
const WALL_LOOK := 12.0 * GX
const WALL_STEP := 20.0 * GX
## The map tables below are decomp field positions (GX), converted where they are read.
## Map-edge box past which a drifting balloon gives up.
const EDGE_MIN := 660.0
const EDGE_MAX_X := 3820.0
const EDGE_MAX_Z := 4460.0
## Station box inside its acre (GX from the acre corner): x 120–520, z 160–320.
const STATION_BOX := Rect2(120.0, 160.0, 400.0, 160.0)
const LOOK_AHEAD := 80.0 * GX
const TURN_CHECKS: Array[int] = [-2500, 0, 2500]
## `birth_pos_data` / `birth_pos_random_data`, indexed by `data_index_data[angle >> 12]`.
const BIRTH_INDEX: Array[int] = [0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 0]
const BIRTH_POS: Array[Vector2] = [
	Vector2(1600, 500), Vector2(500, 500), Vector2(500, 1600), Vector2(500, 4620),
	Vector2(1600, 4620), Vector2(3980, 4620), Vector2(3980, 1600), Vector2(3980, 500),
]
const BIRTH_SPREAD: Array[Vector2] = [
	Vector2(1280, 0), Vector2(960, 960), Vector2(0, 1920), Vector2(960, -960),
	Vector2(1280, 0), Vector2(-960, -960), Vector2(0, 1920), Vector2(-960, 960),
]
## `balloon_prim_data` / `balloon_env_data`.
const PRIM: Array[Color] = [
	Color(1.0, 0.824, 0.784), Color(0.784, 0.902, 0.784), Color(1.0, 0.98, 0.784),
	Color(0.863, 1.0, 0.784), Color(0.941, 0.824, 1.0),
]
const ENV: Array[Color] = [
	Color(1.0, 0.157, 0.0), Color(0.0, 0.706, 1.0), Color(1.0, 0.784, 0.0),
	Color(0.392, 1.0, 0.0), Color(0.784, 0.118, 1.0),
]
## `Matrix_scale(0.01)` on a GLB baked at `PIPELINE_SCALE`.
const MODEL_SCALE := 0.01 * FieldCatalog.GX_TO_METERS / FieldCatalog.PIPELINE_SCALE

const HEAD_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D tex : source_color, filter_nearest;
uniform sampler2D shade : source_color, filter_linear;
uniform vec4 prim : source_color = vec4(1.0);
uniform vec4 env : source_color = vec4(1.0, 0.0, 0.0, 1.0);
void fragment() {
	ALBEDO = mix(env.rgb, prim.rgb, texture(shade, UV).r);
	ALPHA = texture(tex, UV).a;
	ALPHA_SCISSOR_THRESHOLD = 144.0 / 255.0;
}
"""

static var _head_shader: Shader

signal gone(look_up: bool)

var action: Action = Action.BIRTH
## World position (metres).
var pos: Vector3 = Vector3.ZERO
var heading: int = 0
var type_idx: int = 0
var y_offset: float = HEIGHT
## Seconds left drifting (or snagged) before it gives up.
var escape_time: float = DRIFT_SEC
var look_up: bool = false
var tree: Node3D = null
var _hold: float = HOLD_SEC
## The bob's phase, binangle.
var _bob: float = 0.0
var _turned: bool = false
var _count: int = 0
## Rising speed while escaping, m/s.
var _rise: float = 0.0
var _wobble: float = 0.0
var _rng := RandomNumberGenerator.new()
var _world: World
var _balloon: Node3D
var _present: Node3D
var _trees: Dictionary = {}
var _trees_at_ms: int = -1


func _ready() -> void:
	_rng.randomize()
	_world = World.find(get_tree())
	_balloon = _attach(&"act_balloon")
	_present = _attach(&"obj_item_present")
	_tint()
	_birth()
	_place()


func _attach(visual: StringName) -> Node3D:
	var host := Node3D.new()
	add_child(host)
	var vis: Node3D = GeneratedVisual.attach(host, visual)
	if vis != null:
		host.scale = Vector3.ONE * MODEL_SCALE
		var anim: AnimationPlayer = VisualAnimation.find_animation_player(vis)
		if anim != null and anim.get_animation_list().size() > 0:
			var clip: String = anim.get_animation_list()[0]
			var a: Animation = anim.get_animation(clip)
			if a != null:
				## The root joint's keys are in the decomp's frame (chain along -X); the rest
				## pose already stands it up, so only the wires' and head's sway play.
				a = a.duplicate() as Animation
				for t: int in range(a.get_track_count() - 1, -1, -1):
					if String(a.track_get_path(t)).ends_with("joint_0"):
						a.remove_track(t)
				a.loop_mode = Animation.LOOP_LINEAR
				var lib: AnimationLibrary = anim.get_animation_library(&"")
				if lib != null:
					lib.add_animation(StringName(clip), a)
			anim.play(clip)
	return host


## Joint 3 (the head, `act_balloon_head_tex_rgb_ia8`) combines two tiles: an intensity
## shading tile blends env (dark) to prim (the highlight), the IA8 tile cuts the round edge
## (`gDPSetTexEdgeAlpha(144)`). The converter bound only the IA8 tile to the head; the
## shading tile sits on the model's first material.
func _tint() -> void:
	if _head_shader == null:
		_head_shader = Shader.new()
		_head_shader.code = HEAD_SHADER
	var shade: Texture2D = null
	for mi: Node in _balloon.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var first := m.get_active_material(0) as BaseMaterial3D if m.mesh != null and m.mesh.get_surface_count() > 0 else null
		if first != null and not String(first.resource_name).contains("head"):
			shade = first.albedo_texture
	for mi: Node in _balloon.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i: int in (m.mesh.get_surface_count() if m.mesh != null else 0):
			var src := m.get_active_material(i) as BaseMaterial3D
			if src == null or not String(src.resource_name).contains("head"):
				continue
			var mat := ShaderMaterial.new()
			mat.shader = _head_shader
			mat.set_shader_parameter("tex", src.albedo_texture)
			mat.set_shader_parameter("shade", shade)
			mat.set_shader_parameter("prim", PRIM[type_idx])
			mat.set_shader_parameter("env", ENV[type_idx])
			m.set_surface_override_material(i, mat)


## `aFSN_birth_init`.
func _birth() -> void:
	heading = Game.wind.angle_s()
	var idx: int = BIRTH_INDEX[(heading >> 12) & 0xF]
	var p: Vector2 = BIRTH_POS[idx]
	var spread: Vector2 = BIRTH_SPREAD[idx]
	type_idx = _rng.randi_range(0, 4)
	var along_z: bool = false
	if spread.x != 0.0 and spread.y != 0.0:
		along_z = _rng.randi_range(0, 1) == 1
	elif spread.y != 0.0:
		along_z = true
	if along_z:
		p.y += signf(spread.y) * _rng.randf() * absf(spread.y)
	else:
		p.x += signf(spread.x) * _rng.randf() * absf(spread.x)
	var at: Vector3 = _field_to_world(p)
	pos = Vector3(at.x, _ground(at) + BIRTH_HEIGHT, at.z)
	_tint()
	action = Action.MOVING


## Debug / capture: start over `world` instead of at the map edge.
func start_near(world: Vector3) -> void:
	if _world == null:
		return
	pos = Vector3(world.x, _ground(world) + HEIGHT, world.z)
	escape_time = DRIFT_SEC
	_hold = 0.0
	_place()


func _process(delta: float) -> void:
	_step(delta)
	if is_inside_tree():
		_place()


func _step(delta: float) -> void:
	match action:
		Action.MOVING:
			_moving(delta)
		Action.WOOD_STOP:
			_wood_stop(delta)
		Action.ESCAPE:
			_escape(delta)
	if not is_inside_tree() or is_queued_for_deletion():
		return
	if _hold > 0.0:
		_hold = maxf(_hold - delta, 0.0)
	elif action != Action.WOOD_STOP:
		## `Actor_position_moveF`: 1–1.5 GX a frame downwind.
		var speed: float = (Game.wind.power() * 0.5 + 1.0) * DRIFT_SPEED if action == Action.MOVING else 0.0
		var yaw: float = float(heading & 0xFFFF) / 65536.0 * TAU
		pos.x += sin(yaw) * speed * delta
		pos.z += cos(yaw) * speed * delta


func _ease(value: float, target: float, delta: float) -> float:
	return Motion.approach(value, target, EASE_HALF_LIFE, EASE_MAX_SPEED, 0.0, delta)


func _moving(delta: float) -> void:
	if escape_time > 0.0:
		escape_time = maxf(escape_time - delta, 0.0)
	elif _out_of_town():
		_start_escape(false)
		return
	_bob = fmod(_bob + BOB_RATE * delta, 65536.0)
	var want: float = _ground(pos) + y_offset + sin(_bob / 65536.0 * TAU) * BOB
	pos.y = _ease(pos.y, want, delta)
	if _hits_wall():
		y_offset = minf(y_offset + CLIMB_SPEED * delta, HEIGHT_MAX)
	elif y_offset > HEIGHT:
		y_offset = maxf(y_offset - SINK_SPEED * delta, HEIGHT)
	var here: Node3D = _tree_at(pos)
	if here != null:
		var perch: Vector3 = _perch(here)
		var d := Vector2(perch.x - pos.x, perch.z - pos.z)
		var reach: float = SNAG_REACH_CEDAR if _is_cedar(here) else SNAG_REACH
		if d.length() < reach and absf(perch.y - pos.y) < SNAG_HEIGHT:
			tree = here
			_start_snag()
		return
	if not _turned:
		for off: int in TURN_CHECKS:
			var a: int = heading + off
			var yaw: float = float(a & 0xFFFF) / 65536.0 * TAU
			var ahead := Vector3(pos.x + sin(yaw) * LOOK_AHEAD, 0.0, pos.z + cos(yaw) * LOOK_AHEAD)
			if _tree_at(ahead) != null:
				heading = a
				_turned = true
				break
	if not _turned:
		heading = Game.wind.angle_s()


func _start_snag() -> void:
	action = Action.WOOD_STOP
	escape_time = SNAG_SEC + ESCAPE_SEC
	_count = 0
	if tree != null and tree.has_signal("shaken"):
		tree.connect("shaken", _on_tree_shaken)


func _wood_stop(delta: float) -> void:
	escape_time -= delta
	if escape_time <= ESCAPE_SEC or tree == null or not is_instance_valid(tree):
		_start_escape(false)
		return
	var perch: Vector3 = _perch(tree)
	if Vector2(pos.x - perch.x, pos.z - perch.z).length() > PERCH_SETTLE:
		pos.x = _ease(pos.x, perch.x, delta)
		pos.y = _ease(pos.y, perch.y, delta)
		pos.z = _ease(pos.z, perch.z, delta)
	if _wobble > 0.0:
		_wobble = maxf(_wobble - delta, 0.0)


func _on_tree_shaken(big: bool) -> void:
	if action != Action.WOOD_STOP:
		return
	if big:
		_start_escape(true)
	else:
		_wobble = WOBBLE_SEC
		_count += 1


## `aFSN_escape_init`: shaken free (the present falls) or giving up (it keeps it).
func _start_escape(shaken: bool) -> void:
	if tree != null and is_instance_valid(tree) and tree.is_connected("shaken", _on_tree_shaken):
		tree.disconnect("shaken", _on_tree_shaken)
	action = Action.ESCAPE
	_rise = 0.0
	look_up = false
	if shaken:
		if tree != null and is_instance_valid(tree) and tree.has_method("drop_present"):
			tree.call("drop_present", ItemCatalog.get_item(true_present(_rng)))
		_present.visible = false
	else:
		escape_time = ESCAPE_SEC
		var p: Node3D = Player.find(get_tree()) as Node3D
		if p != null and p.global_position.distance_to(global_position) < FieldCatalog.ACRE_METERS:
			look_up = true


func _escape(delta: float) -> void:
	## Rises, speeding up to 5 GX a frame, and is gone 500 GX over the ground.
	var start: float = _rise
	_rise = minf(_rise + RISE_ACCEL * delta, RISE_MAX)
	var ramp: float = (_rise - start) / RISE_ACCEL
	pos.y += 0.5 * (start + _rise) * ramp + _rise * (delta - ramp)
	if pos.y > _ground(pos) + LEAVE_HEIGHT:
		gone.emit(look_up)
		queue_free()


## `mPr_DummyPresentToTruePresent`: 80% a piece from the rare (C) list, else a fruit from out of town.
static func true_present(r: RandomNumberGenerator) -> StringName:
	if r.randi_range(0, 4) != 0:
		var ftr: StringName = FurnitureCatalog.pick_named("ftr", "C", r)
		if ftr != &"":
			return ftr
	var own: StringName = Game.town.town_fruit if Game != null else &"apple"
	var others: Array[StringName] = []
	for f: StringName in ShopBook.FRUITS:
		if f != own:
			others.append(f)
	return others[r.randi_range(0, others.size() - 1)] if not others.is_empty() else &"apple"


func _out_of_town() -> bool:
	var field: Vector2 = _world_to_field(pos)
	if field.x <= EDGE_MIN or field.x >= EDGE_MAX_X or field.y <= EDGE_MIN or field.y >= EDGE_MAX_Z:
		return true
	var mgr: EventManager = EventManager.find(get_tree())
	if mgr == null:
		return false
	var station: Vector2i = mgr.block_of("station")
	if station.x < 0:
		return false
	var local := Vector2(field.x - station.x * 640.0, field.y - station.y * 640.0)
	return STATION_BOX.has_point(local)


## --- Map edge: decomp field positions (GX) ↔ the world ---------------------------------------
## The field counts from its border ring, 16 units (640 GX) in from the grid's corner.


func _field_to_world(field: Vector2) -> Vector3:
	if _world == null or _world.grid == null:
		return Vector3(field.x, 0.0, field.y) * GX
	var cs: float = _world.grid.cell_size
	return _world.grid.origin + Vector3((field.x / 40.0 - 16.0) * cs, 0.0, (field.y / 40.0 - 16.0) * cs)


func _world_to_field(world: Vector3) -> Vector2:
	if _world == null or _world.grid == null:
		return Vector2(world.x, world.z) / GX
	var cs: float = _world.grid.cell_size
	var rel: Vector3 = world - _world.grid.origin
	return Vector2((rel.x / cs + 16.0) * 40.0, (rel.z / cs + 16.0) * 40.0)


func _cell_of(world: Vector3) -> Vector2i:
	return _world.grid.world_to_cell(world)


## `mCoBG_GetBalloonGroundY` (the sea counts as one unit up), metres.
func _ground(world: Vector3) -> float:
	if _world == null or _world.layout == null:
		return 0.0
	var cell: Vector2i = _cell_of(world)
	if not _world.layout.is_in_bounds(cell):
		cell = Vector2i(clampi(cell.x, 0, _world.grid.columns - 1), clampi(cell.y, 0, _world.grid.rows - 1))
	return FieldCollision.ground_y(_world.layout, cell)


## `mCoBG_BgCheckControll(…, 12, …)` hitting a wall: the ground just ahead steps up (a cliff).
func _hits_wall() -> bool:
	var yaw: float = float(heading & 0xFFFF) / 65536.0 * TAU
	var here: float = _ground(pos)
	var ahead: float = _ground(pos + Vector3(sin(yaw), 0.0, cos(yaw)) * WALL_LOOK)
	return ahead > here + WALL_STEP


## `mFI_GetUnitFG` is a tree the balloon can snag on (cells cached, re-read every 2 s).
func _tree_at(world: Vector3) -> Node3D:
	if _world == null or _world.grid == null:
		return null
	var now: int = Time.get_ticks_msec()
	if _trees_at_ms < 0 or now - _trees_at_ms > 2000:
		_trees_at_ms = now
		_trees.clear()
		for node: Node in get_tree().get_nodes_in_group("plant"):
			if node is Node3D and node.has_method("can_catch_balloon"):
				_trees[_world.grid.world_to_cell((node as Node3D).global_position)] = node
	var n: Variant = _trees.get(_cell_of(world))
	if n == null or not is_instance_valid(n) or not bool((n as Node3D).call("can_catch_balloon")):
		return null
	return n as Node3D


func _is_cedar(t: Node3D) -> bool:
	return t.has_method("_family") and int(t.call("_family")) == PlantData.Family.CEDAR


func _perch(t: Node3D) -> Vector3:
	return t.call("balloon_perch")


func _place() -> void:
	global_position = pos
	## The tilt flips every 4 frames of the wobble.
	var wobble_frame: int = int(_wobble * FRAME_HZ)
	rotation.z = deg_to_rad(2.7) * (1.0 if wobble_frame & 4 == 0 else -1.0) if _wobble > 0.0 else 0.0
