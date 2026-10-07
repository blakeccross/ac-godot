class_name MeteorShower
extends Node3D

## Shooting stars on the pond at the Meteor Shower (`ef_shooting_set` → `ef_shooting` →
## `ef_shooting_kira`). The set sits over the pond acre's centre, 20 GX above its base, and
## every so often (600 frames, quickening to 120 at 19:30 and back by 21:00, ±60) sends one
## while the camera is on the pond. A star is the flat strip `ef_nagare01` reflected on the
## water, halfway between the pond and the player, at 315° ±34°: its 8×256 tile scrolls the
## 32-row streak through the strip (frames ~99–141 of 320), after a sparkle
## (`ef_takurami01_kira`) has run the same line at frame 76.

const SET_LIFT_GX := 20.0
const STAR_LIFE := 320
const KIRA_AT := 76
const KIRA_LIFE := 42
const KIRA_RUN_GX := 115.0
const SCATTER_GX := 80.0
## `Matrix_scale(0.01, 0.01, 0.01 · len)`.
const STAR_SCALE := 0.01
## After the pond water (`VisualWaterMaterials`, priority 2), like `PondMoon`.
const PRIORITY := 3
const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
uniform sampler2D tex : source_color, filter_nearest, repeat_disable;
// `two_tex_scroll_dolphin(…, 0, y, 8, 256, …)`: the strip's UVs cover 32 of the tile's 256
// rows; `scroll` shifts them in texels.
uniform float scroll = 0.0;
void fragment() {
	float row = UV.y * 256.0 + scroll;
	if (row < 0.0 || row >= 32.0) {
		discard;
	}
	vec4 t = texture(tex, vec2(UV.x, row / 32.0));
	ALBEDO = t.rgb;
	ALPHA = t.a;
}
"""

var pond_center: Vector3 = Vector3.INF
var _shader: Shader
var _rng := RandomNumberGenerator.new()
var _frame: float = 0.0
var _last_frame: int = -1
var _count: int = 0
var _next: int = 600
var _stars: Array[Dictionary] = []


const GROUP := &"meteor_shower"


func _ready() -> void:
	add_to_group(GROUP)
	_rng.randomize()
	_shader = Shader.new()
	_shader.code = SHADER
	_next = next_interval(Clock.hour * 3600 + Clock.minute * 60, _rng)


## `eShootingSet_GetFrame_MakeNextShooting`: 600 frames outside 18:00–21:00, down to 120 at
## 19:30, plus or minus 60.
static func next_interval(now_sec: int, rng: RandomNumberGenerator) -> int:
	var base: float = 600.0
	if now_sec >= 64800 and now_sec < 70200:
		base = lerpf(600.0, 120.0, float(now_sec - 64800) / 5400.0)
	elif now_sec >= 70200 and now_sec < 75600:
		base = lerpf(120.0, 600.0, float(now_sec - 70200) / 5400.0)
	return int(base) + int(rng.randf() * 120.0 - 60.0)


## The streak's texel offset at a star's frame `t`: `-(t − 120) · 6` quarter texels.
static func scroll_at(t: int) -> float:
	return -float(t - 120) * 1.5


func _process(delta: float) -> void:
	_frame += delta * DecompTime.TICK_HZ
	var now: int = int(_frame)
	while _last_frame < now:
		_last_frame += 1
		_tick()


func _tick() -> void:
	if _count >= _next:
		_count = 0
		_next = next_interval(Clock.hour * 3600 + Clock.minute * 60, _rng)
		if _looking_at_pond():
			_launch()
	_count += 1
	for star: Dictionary in _stars.duplicate():
		_tick_star(star)


func _set_position() -> Vector3:
	var c: Vector3 = pond_center if pond_center != Vector3.INF else global_position
	return c + Vector3(0.0, SET_LIFT_GX * FieldCatalog.GX_TO_METERS, 0.0)


## `check_lookat_block_proc`: the camera follows the player, so the player is in the pond acre.
func _looking_at_pond() -> bool:
	var player: Node3D = Player.find(get_tree()) as Node3D if is_inside_tree() else null
	var world := World.find(get_tree()) if is_inside_tree() else null
	if player == null or world == null or world.grid == null:
		return false
	var a: Vector2i = world.grid.world_to_cell(player.global_position) / 16
	var b: Vector2i = world.grid.world_to_cell(_set_position()) / 16
	return a == b


## Send one now (debug console), as if the player stood at the pond.
func launch_now() -> void:
	_launch(false)


func _launch(toward_player: bool = true) -> void:
	var player: Node3D = Player.find(get_tree()) as Node3D if toward_player else null
	var pos: Vector3 = _set_position()
	if player != null:
		pos.x = (pos.x + player.global_position.x) * 0.5
		pos.z = (pos.z + player.global_position.z) * 0.5
	## The decomp spreads both axes by the same cosine, so the scatter runs diagonally.
	var spread: float = _rng.randf() * SCATTER_GX * FieldCatalog.GX_TO_METERS * cos(_rng.randf() * TAU)
	pos.x += spread
	pos.z += spread
	var side: float = 1.0 if (_rng.randi_range(0, 9) & 1) == 1 else -1.0
	var yaw: float = deg_to_rad(315.0) + side * _rng.randf() * (6144.0 / 65536.0 * TAU)
	var length: float = (_rng.randf() * 30.0 + 70.0) * 0.01
	var root := Node3D.new()
	root.top_level = true
	add_child(root)
	root.global_position = pos
	var strip: Node3D = _visual(root, &"ef_nagare01")
	var mats: Array[ShaderMaterial] = []
	_shade(strip, mats)
	_stars.append({
		"t": 0, "node": root, "strip": strip, "mats": mats, "yaw": yaw, "len": length, "pos": pos,
		"wobble": 0, "kira": null,
	})


func _tick_star(star: Dictionary) -> void:
	var t: int = int(star["t"])
	if t >= STAR_LIFE:
		(star["node"] as Node).queue_free()
		_stars.erase(star)
		return
	star["wobble"] = int(star["wobble"]) + 256
	var w: float = float(int(star["wobble"]) & 0xFFFF) / 65536.0 * TAU
	var s: float = STAR_SCALE * FieldCatalog.GX_TO_METERS / FieldCatalog.PIPELINE_SCALE
	var strip := star["strip"] as Node3D
	## `RotateY(−w) · scale(1.035, 1, 1) · RotateY(w) · RotateY(yaw) · scale(…, len)`.
	strip.basis = (Basis(Vector3.UP, -w) * Basis.from_scale(Vector3(1.035, 1.0, 1.0)) * Basis(Vector3.UP, w)
		* Basis(Vector3.UP, float(star["yaw"])) * Basis.from_scale(Vector3(s, s, s * float(star["len"]))))
	for mat: ShaderMaterial in star["mats"]:
		mat.set_shader_parameter("scroll", scroll_at(t))
	if t == KIRA_AT:
		star["kira"] = {"t": 0, "node": _visual(star["node"] as Node3D, &"ef_takurami01_kira")}
	if star["kira"] != null:
		_tick_kira(star)
	star["t"] = t + 1


## `eShootingKira_mv/dw`: a sparkle that grows, spins twice and runs 230 GX along the line.
func _tick_kira(star: Dictionary) -> void:
	var kira: Dictionary = star["kira"]
	var c: int = int(kira["t"])
	var node := kira["node"] as Node3D
	if c >= KIRA_LIFE:
		node.queue_free()
		star["kira"] = null
		return
	var m: float = float(KIRA_LIFE)
	var scale: float
	if c < int(m * 0.7):
		scale = lerpf(0.0, 0.0065, float(c) / (m * 0.7))
	elif c < int(m * 0.87):
		scale = lerpf(0.0065, 0.00975, (float(c) - m * 0.7) / (m * 0.17))
	else:
		scale = lerpf(0.00975, 0.0, clampf((float(c) - m * 0.7) / (m * 0.3), 0.0, 1.0))
	var run: float = KIRA_RUN_GX * float(star["len"]) * FieldCatalog.GX_TO_METERS
	var yaw: float = float(star["yaw"])
	var dir := Vector3(sin(yaw), 0.0, cos(yaw))
	var at: Vector3 = (star["pos"] as Vector3) + dir * lerpf(-run, run, float(c) / m)
	var spin: float = float(c) / m * 2.0 * TAU
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	var face: Basis = cam.global_basis if cam != null else Basis.IDENTITY
	var s: float = scale * FieldCatalog.GX_TO_METERS / FieldCatalog.PIPELINE_SCALE
	node.global_transform = Transform3D(face * Basis(Vector3.BACK, spin) * Basis.from_scale(Vector3.ONE * s), at)
	kira["t"] = c + 1


func _visual(root: Node3D, visual: StringName) -> Node3D:
	var host := Node3D.new()
	root.add_child(host)
	var paths: PackedStringArray = FieldCatalog.mesh_paths(visual)
	if paths.is_empty() or not ResourceLoader.exists(paths[0]):
		return host
	var packed: PackedScene = load(paths[0]) as PackedScene
	if packed != null:
		var inst: Node = packed.instantiate()
		host.add_child(inst)
		_after_water(inst)
	return host


func _after_water(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i: int in (mi.mesh.get_surface_count() if mi.mesh != null else 0):
			var src: Material = mi.get_active_material(i)
			if src != null:
				var own: Material = src.duplicate()
				own.render_priority = PRIORITY
				mi.set_surface_override_material(i, own)
	for child: Node in node.get_children():
		_after_water(child)


func _shade(node: Node, out: Array[ShaderMaterial]) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i: int in (mi.mesh.get_surface_count() if mi.mesh != null else 0):
			var mat := ShaderMaterial.new()
			mat.shader = _shader
			mat.render_priority = PRIORITY
			var src: Material = mi.get_active_material(i)
			if src is BaseMaterial3D:
				mat.set_shader_parameter("tex", (src as BaseMaterial3D).albedo_texture)
			mi.set_surface_override_material(i, mat)
			out.append(mat)
	for child: Node in node.get_children():
		_shade(child, out)
