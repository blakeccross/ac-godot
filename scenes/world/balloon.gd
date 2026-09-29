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
## Positions are kept in decomp world units (GX, the whole map including the border acres).

enum Action { BIRTH, MOVING, WOOD_STOP, ESCAPE }

const FRAME_HZ := DecompTime.FRAME_HZ
## `aFSN_ESCAPE_TIMER`, the drifting grace period, the snag time.
const ESCAPE_TIMER := 1554
const DRIFT_FRAMES := 2000
const SNAG_FRAMES := 18000
const HEIGHT_GX := 110.0
const HEIGHT_MAX_GX := 300.0
const BIRTH_HEIGHT_GX := 200.0
const LEAVE_HEIGHT_GX := 500.0
const BOB_STEP := 250
const BOB_GX := 10.0
## `add_calc(…, 1 - sqrt(0.7), 0.5, 0)`.
const EASE := 0.16333997
const EASE_MAX_GX := 0.5
## Map-edge box (GX) past which a drifting balloon gives up.
const EDGE_MIN := 660.0
const EDGE_MAX_X := 3820.0
const EDGE_MAX_Z := 4460.0
## Station box inside its acre (GX from the acre corner): x 120–520, z 160–320.
const STATION_BOX := Rect2(120.0, 160.0, 400.0, 160.0)
const LOOK_AHEAD_GX := 80.0
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
## Position in GX; `pos.y` absolute.
var pos: Vector3 = Vector3.ZERO
var heading: int = 0
var type_idx: int = 0
var y_offset: float = HEIGHT_GX
var escape_timer: int = DRIFT_FRAMES
var look_up: bool = false
var tree: Node3D = null
## Frames before it starts moving (`timer = 10`).
var _hold: int = 10
var _bob: int = 0
var _turned: bool = false
var _count: int = 0
var _rise: float = 0.0
var _wobble: float = 0.0
var _frame_acc: float = 0.0
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
	heading = Wind.angle_s()
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
	pos = Vector3(p.x, _ground(Vector2(p.x, p.y)) + BIRTH_HEIGHT_GX, p.y)
	_tint()
	action = Action.MOVING


## Debug / capture: start over `world` instead of at the map edge.
func start_near(world: Vector3) -> void:
	if _world == null:
		return
	var gx: Vector3 = _to_gx(world)
	pos = Vector3(gx.x, _ground(Vector2(gx.x, gx.z)) + HEIGHT_GX, gx.z)
	escape_timer = DRIFT_FRAMES
	_hold = 0
	_place()


func _process(delta: float) -> void:
	_frame_acc += delta * FRAME_HZ
	while _frame_acc >= 1.0:
		_frame_acc -= 1.0
		_step()
		if not is_inside_tree():
			return
	_place()


func _step() -> void:
	match action:
		Action.MOVING:
			_moving()
		Action.WOOD_STOP:
			_wood_stop()
		Action.ESCAPE:
			_escape()
	if _hold > 0:
		_hold -= 1
	elif action != Action.WOOD_STOP:
		## `Actor_position_moveF`.
		var speed: float = Wind.power() * 0.5 + 1.0 if action == Action.MOVING else 0.0
		var yaw: float = float(heading & 0xFFFF) / 65536.0 * TAU
		pos.x += sin(yaw) * speed
		pos.z += cos(yaw) * speed


func _moving() -> void:
	if escape_timer > 0:
		escape_timer -= 1
	elif _out_of_town():
		_start_escape(false)
		return
	_bob += BOB_STEP
	var want: float = _ground(Vector2(pos.x, pos.z)) + y_offset + sin(float(_bob & 0xFFFF) / 65536.0 * TAU) * BOB_GX
	pos.y += clampf((want - pos.y) * EASE, -EASE_MAX_GX, EASE_MAX_GX)
	if _hits_wall():
		y_offset = minf(y_offset + 0.05, HEIGHT_MAX_GX)
	elif y_offset > HEIGHT_GX:
		y_offset -= 0.005
	var here: Node3D = _tree_at(Vector2(pos.x, pos.z))
	if here != null:
		var perch: Vector3 = _perch_gx(here)
		var d := Vector2(perch.x - pos.x, perch.z - pos.z)
		var r2: float = 484.0 if _is_cedar(here) else 225.0
		if d.length_squared() < r2 and (perch.y - pos.y) * (perch.y - pos.y) < 225.0:
			tree = here
			_start_snag()
		return
	if not _turned:
		for off: int in TURN_CHECKS:
			var a: int = heading + off
			var yaw: float = float(a & 0xFFFF) / 65536.0 * TAU
			var ahead := Vector2(pos.x + sin(yaw) * LOOK_AHEAD_GX, pos.z + cos(yaw) * LOOK_AHEAD_GX)
			if _tree_at(ahead) != null:
				heading = a
				_turned = true
				break
	if not _turned:
		heading = Wind.angle_s()


func _start_snag() -> void:
	action = Action.WOOD_STOP
	escape_timer = SNAG_FRAMES + ESCAPE_TIMER
	_count = 0
	if tree != null and tree.has_signal("shaken"):
		tree.connect("shaken", _on_tree_shaken)


func _wood_stop() -> void:
	escape_timer -= 1
	if escape_timer <= ESCAPE_TIMER or tree == null or not is_instance_valid(tree):
		_start_escape(false)
		return
	var perch: Vector3 = _perch_gx(tree)
	if Vector2(pos.x - perch.x, pos.z - perch.z).length() > 2.0:
		pos.x += clampf((perch.x - pos.x) * EASE, -EASE_MAX_GX, EASE_MAX_GX)
		pos.y += clampf((perch.y - pos.y) * EASE, -EASE_MAX_GX, EASE_MAX_GX)
		pos.z += clampf((perch.z - pos.z) * EASE, -EASE_MAX_GX, EASE_MAX_GX)
	if _wobble > 0.0:
		_wobble -= 1.0


func _on_tree_shaken(big: bool) -> void:
	if action != Action.WOOD_STOP:
		return
	if big:
		_start_escape(true)
	else:
		_wobble = 12.0
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
		escape_timer = ESCAPE_TIMER
		var p: Node3D = Player.find(get_tree()) as Node3D
		if p != null and p.global_position.distance_to(global_position) < FieldCatalog.ACRE_METERS:
			look_up = true


func _escape() -> void:
	## Rises, speeding up to 5 GX a frame, and is gone 500 GX over the ground.
	_rise = minf(_rise + 0.5, 5.0)
	pos.y += _rise
	if pos.y > _ground(Vector2(pos.x, pos.z)) + LEAVE_HEIGHT_GX:
		gone.emit(look_up)
		queue_free()


## `mPr_DummyPresentToTruePresent`: 80% a piece from the rare (C) list, else a fruit from out of town.
static func true_present(r: RandomNumberGenerator) -> StringName:
	if r.randi_range(0, 4) != 0:
		var ftr: StringName = FtrCatalog.pick_named("ftr", "C", r)
		if ftr != &"":
			return ftr
	var own: StringName = Game.town_fruit if Game != null else &"apple"
	var others: Array[StringName] = []
	for f: StringName in ShopBook.FRUITS:
		if f != own:
			others.append(f)
	return others[r.randi_range(0, others.size() - 1)] if not others.is_empty() else &"apple"


func _out_of_town() -> bool:
	if pos.x <= EDGE_MIN or pos.x >= EDGE_MAX_X or pos.z <= EDGE_MIN or pos.z >= EDGE_MAX_Z:
		return true
	var mgr: EventManager = EventManager.find(get_tree())
	if mgr == null:
		return false
	var station: Vector2i = mgr.block_of("station")
	if station.x < 0:
		return false
	var local := Vector2(pos.x - station.x * 640.0, pos.z - station.y * 640.0)
	return STATION_BOX.has_point(local)


## --- Map helpers (GX ↔ world) -------------------------------------------------------------


func _cell_of(gx: Vector2) -> Vector2i:
	return Vector2i(floori(gx.x / 40.0) - 16, floori(gx.y / 40.0) - 16)


func _to_world(gx: Vector3) -> Vector3:
	if _world == null or _world.grid == null:
		return gx * FieldCatalog.GX_TO_METERS
	var cs: float = _world.grid.cell_size
	return _world.grid.origin + Vector3((gx.x / 40.0 - 16.0) * cs, gx.y * FieldCatalog.GX_TO_METERS, (gx.z / 40.0 - 16.0) * cs)


func _to_gx(world: Vector3) -> Vector3:
	var cs: float = _world.grid.cell_size
	var rel: Vector3 = world - _world.grid.origin
	return Vector3((rel.x / cs + 16.0) * 40.0, world.y / FieldCatalog.GX_TO_METERS, (rel.z / cs + 16.0) * 40.0)


## `mCoBG_GetBalloonGroundY` (the sea counts as one unit up).
func _ground(gx: Vector2) -> float:
	if _world == null or _world.layout == null:
		return 0.0
	var cell: Vector2i = _cell_of(gx)
	if not _world.layout.is_in_bounds(cell):
		cell = Vector2i(clampi(cell.x, 0, _world.grid.columns - 1), clampi(cell.y, 0, _world.grid.rows - 1))
	return FieldCollision.ground_y(_world.layout, cell) / FieldCatalog.GX_TO_METERS


## `mCoBG_BgCheckControll(…, 12, …)` hitting a wall: the ground 12 GX ahead steps up (a cliff).
func _hits_wall() -> bool:
	var yaw: float = float(heading & 0xFFFF) / 65536.0 * TAU
	var here: float = _ground(Vector2(pos.x, pos.z))
	var ahead: float = _ground(Vector2(pos.x + sin(yaw) * 12.0, pos.z + cos(yaw) * 12.0))
	return ahead > here + 20.0


## `mFI_GetUnitFG` is a tree the balloon can snag on (cells cached, re-read every 2 s).
func _tree_at(gx: Vector2) -> Node3D:
	if _world == null or _world.grid == null:
		return null
	var now: int = Time.get_ticks_msec()
	if _trees_at_ms < 0 or now - _trees_at_ms > 2000:
		_trees_at_ms = now
		_trees.clear()
		for node: Node in get_tree().get_nodes_in_group("plant"):
			if node is Node3D and node.has_method("can_catch_balloon"):
				_trees[_world.grid.world_to_cell((node as Node3D).global_position)] = node
	var n: Variant = _trees.get(_cell_of(gx))
	if n == null or not is_instance_valid(n) or not bool((n as Node3D).call("can_catch_balloon")):
		return null
	return n as Node3D


func _is_cedar(t: Node3D) -> bool:
	return t.has_method("_family") and int(t.call("_family")) == PlantData.Family.CEDAR


func _perch_gx(t: Node3D) -> Vector3:
	return _to_gx(t.call("balloon_perch"))


func _place() -> void:
	global_position = _to_world(pos)
	rotation.z = deg_to_rad(2.7) * (1.0 if int(_wobble) & 4 == 0 else -1.0) if _wobble > 0.0 else 0.0
