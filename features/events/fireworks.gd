class_name Fireworks
extends Node3D

## The fireworks over the pond (`ef_hanabi_switch` → `ef_hanabi_set` → the shells
## `ef_hanabi_hoshi` / `_botan1` / `_botan2` / `_yanagi`). Every 300 frames the switch launches
## a set (40 frames in); a set fires its shells at fixed frames (`eHanabiSet_sqdt*`), each a
## flat disc (`ef_hanabi_*_00`, laid flat by `RotateX(270)`) that grows toward its size,
## spins and wobbles, and runs its prim/env colours through a morph table
## (`eEC_MorphCombine`), with a light flash at frame 10 and the bang at frame 72. Sets fire
## halfway between the pond and the player. In the show's last hour the bigger sets 5–8 play.
##
## The timetables are the decomp's, in ticks (60ths of a second); sets and shells keep their
## age in seconds and read the tables at `age * TICK_HZ`, firing each entry as a step
## crosses it.

enum Shell { HOSHI, BOTAN1, BOTAN2, YANAGI }

const CYCLE := 300
const LAUNCH_AT := 40
const SET_LIFE := 200
## `eHanabiSet_sqdt1..8`: `[frame, shell]`.
const SETS: Array = [
	[[0, Shell.HOSHI], [30, Shell.HOSHI], [50, Shell.HOSHI], [120, Shell.BOTAN1], [190, Shell.BOTAN1]],
	[[0, Shell.BOTAN1], [50, Shell.BOTAN1], [80, Shell.BOTAN1], [140, Shell.BOTAN2], [190, Shell.BOTAN2]],
	[[0, Shell.YANAGI], [50, Shell.YANAGI], [80, Shell.YANAGI], [140, Shell.BOTAN2], [190, Shell.BOTAN2]],
	[[0, Shell.HOSHI], [50, Shell.YANAGI], [80, Shell.YANAGI], [140, Shell.BOTAN1], [190, Shell.BOTAN1]],
	[[0, Shell.HOSHI], [20, Shell.HOSHI], [50, Shell.BOTAN2], [90, Shell.BOTAN2], [140, Shell.HOSHI],
		[160, Shell.BOTAN1], [170, Shell.BOTAN1], [170, Shell.BOTAN1]],
	[[0, Shell.BOTAN1], [20, Shell.BOTAN2], [50, Shell.BOTAN2], [90, Shell.YANAGI], [140, Shell.YANAGI],
		[160, Shell.HOSHI], [170, Shell.BOTAN2], [170, Shell.BOTAN2]],
	[[0, Shell.BOTAN2], [20, Shell.BOTAN2], [50, Shell.HOSHI], [90, Shell.HOSHI], [140, Shell.YANAGI],
		[160, Shell.YANAGI], [170, Shell.YANAGI], [170, Shell.YANAGI]],
	[[0, Shell.YANAGI], [10, Shell.YANAGI], [20, Shell.YANAGI], [30, Shell.YANAGI], [140, Shell.BOTAN2],
		[160, Shell.BOTAN2], [170, Shell.BOTAN2], [190, Shell.BOTAN2]],
]
## `[start, end, morph, from, to]` × 9 → prim r,g,b,a, lod, env r,g,b,a (`eEC_morph_data_c`).
const M_HOSHI_1 := [[0, 0, false, 255, 255], [0, 0, false, 200, 200], [0, 0, false, 200, 200],
	[29, 39, true, 150, 0], [10, 24, true, 0, 255], [0, 0, false, 255, 255], [0, 0, false, 0, 0],
	[0, 0, false, 100, 100], [0, 0, false, 255, 255]]
const M_HOSHI_2 := [[0, 0, false, 255, 255], [0, 0, false, 255, 255], [0, 0, false, 255, 255],
	[29, 39, true, 150, 0], [10, 24, true, 0, 255], [0, 0, false, 0, 0], [0, 0, false, 255, 255],
	[0, 0, false, 0, 0], [0, 0, false, 255, 255]]
const M_BOTAN1_1 := [[0, 0, false, 255, 255], [0, 0, false, 255, 255], [34, 44, true, 0, 100],
	[44, 54, true, 150, 0], [10, 34, true, 0, 255], [0, 0, false, 255, 255], [0, 0, false, 0, 0],
	[34, 44, true, 100, 255], [0, 0, false, 255, 255]]
const M_BOTAN1_2 := [[0, 0, false, 255, 255], [0, 0, false, 255, 255], [34, 44, true, 0, 50],
	[44, 54, true, 150, 0], [10, 34, true, 0, 255], [0, 0, false, 0, 0], [0, 0, false, 255, 255],
	[34, 44, false, 50, 255], [0, 0, false, 255, 255]]
const M_BOTAN2_OUT := [[34, 44, true, 255, 0], [0, 0, false, 255, 255], [0, 0, false, 255, 255],
	[44, 54, true, 150, 0], [9, 34, true, 0, 255], [9, 34, true, 255, 0], [0, 0, false, 0, 0],
	[0, 0, false, 255, 255], [0, 0, false, 255, 255]]
const M_BOTAN2_IN := [[0, 0, false, 255, 255], [0, 0, false, 255, 255], [0, 0, false, 0, 0],
	[44, 54, true, 150, 0], [14, 34, true, 0, 255], [0, 0, false, 255, 255], [0, 0, false, 0, 0],
	[14, 34, true, 0, 255], [0, 0, false, 255, 255]]
const M_YANAGI_OUT := [[0, 0, false, 255, 255], [34, 54, true, 255, 200], [34, 54, true, 50, 100],
	[34, 54, true, 150, 0], [5, 34, true, 0, 255], [0, 0, false, 255, 255], [0, 0, false, 0, 0],
	[0, 0, false, 200, 200], [0, 0, false, 255, 255]]
const M_YANAGI_IN := [[0, 0, false, 255, 255], [34, 49, true, 255, 200], [34, 49, true, 50, 100],
	[34, 49, true, 180, 0], [5, 34, true, 0, 255], [0, 0, false, 255, 255], [0, 0, false, 0, 0],
	[0, 0, false, 200, 200], [0, 0, false, 255, 255]]
## Per shell: model, lifetime, `add_calc2` target scale, the outer morph tables (one picked at
## random when there are two), an inner disc at 0.6 with its own table, flash colours, bang.
const SHELLS: Dictionary = {
	Shell.HOSHI: {"visual": &"ef_hanabi_h_00", "life": 80, "size": 0.025, "morph": [M_HOSHI_1, M_HOSHI_2],
		"inner": [], "light": [Color(0.235, 0.118, 0.118), Color(0.118, 0.235, 0.118)], "se": &"hanabi2"},
	Shell.BOTAN1: {"visual": &"ef_hanabi_b_00", "life": 110, "size": 0.07, "morph": [M_BOTAN1_1, M_BOTAN1_2],
		"inner": [], "light": [Color(0.294, 0.176, 0.118), Color(0.118, 0.353, 0.118)], "se": &"hanabi0"},
	Shell.BOTAN2: {"visual": &"ef_hanabi_b_00", "life": 110, "size": 0.08, "morph": [M_BOTAN2_OUT],
		"inner": M_BOTAN2_IN, "light": [Color(0.235, 0.059, 0.353)], "se": &"hanabi1"},
	Shell.YANAGI: {"visual": &"ef_hanabi_y_00", "life": 110, "size": 0.06, "morph": [M_YANAGI_OUT],
		"inner": M_YANAGI_IN, "light": [Color(0.353, 0.353, 0.176)], "se": &"hanabi3"},
}
## Lengths in metres, from the decomp's GX.
const GX := FieldCatalog.GX_TO_METERS
## `eHanabiSet_SearchNicePos` / `eHanabiSet_mv`.
const SET_LIFT := 20.0 * GX
const SET_BACK := 40.0 * GX
const SCATTER := 125.0 * GX
## The shell drifts round in a 2 GX circle as it spins.
const DRIFT := 2.0 * GX
const BANG_FRAME := 72
const FLASH_FRAME := 10
## `add_calc2(&scale, size, CALC_EASE(0.2), 5)` a tick.
static var EASE_HALF_LIFE: float = Motion.half_life_from_fraction(0.10557281)
const EASE_MAX_SPEED := 5.0 * DecompTime.TICK_HZ
## The shell spins 0x100 and wobbles 0x300 binangle a tick.
const SPIN_RATE := 0x100 * DecompTime.TICK_HZ
const WOBBLE_RATE := 0x300 * DecompTime.TICK_HZ
## The disc is one quad with UVs 0–2 over a quarter texture, mirrored (`G_TX_MIRROR`); the
## texture is an intensity mask coloured by the prim/env combiner — IA8 (`b`) carries its
## own alpha, I4 (`h`, `y`) uses the intensity for both (`IIII`).
const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
uniform sampler2D tex : source_color, filter_nearest;
uniform vec4 prim = vec4(1.0);
uniform vec4 env = vec4(0.0);
uniform bool alpha_from_i = false;
void fragment() {
	vec2 uv = vec2(1.0) - abs(vec2(1.0) - UV);
	vec4 t = texture(tex, uv);
	float a = alpha_from_i ? t.r : t.a;
	ALBEDO = mix(env.rgb, prim.rgb, t.r);
	ALPHA = a * prim.a;
}
"""

## Pond centre (world) and whether the show is in its last hour (`effect_specific[1]`).
var pond_center: Vector3 = Vector3.INF
var finale: bool = false
## Keep looping (the show) or stop after one set (the countdown's single switch).
var looping: bool = true

## Seconds since the switch started, and the tick the next set launches on.
var _time: float = 0.0
var _next_launch: float = LAUNCH_AT
var _sets: Array = []
var _shells: Array = []
var _rng := RandomNumberGenerator.new()
var _shader: Shader
var _light: OmniLight3D
var _light_left: float = 0.0
var _light_color: Color = Color.BLACK


func _ready() -> void:
	_rng.randomize()
	_shader = Shader.new()
	_shader.code = SHADER
	_light = OmniLight3D.new()
	_light.omni_range = 60.0
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	add_child(_light)


func _process(delta: float) -> void:
	_step(delta)
	_update_light(delta)


func _step(delta: float) -> void:
	_time += delta
	var now: float = _time * DecompTime.TICK_HZ
	## A set launches at tick 40 of every 300 (the first only, unless the show loops).
	while _next_launch <= now + 0.0001:
		if looping or _next_launch < CYCLE:
			var idx: int = _rng.randi_range(0, 3) + (4 if finale else 0)
			## Aged from its launch tick, so a long step still fires its early shells.
			_sets.append({"set": idx, "age": (now - _next_launch) / DecompTime.TICK_HZ, "fired": -1.0})
		_next_launch += CYCLE
	for set_: Dictionary in _sets.duplicate():
		var t: float = float(set_["age"]) * DecompTime.TICK_HZ
		for entry: Array in SETS[int(set_["set"])]:
			if float(entry[0]) > float(set_["fired"]) and float(entry[0]) <= t + 0.0001:
				_fire(int(entry[1]))
		set_["fired"] = t
		set_["age"] = float(set_["age"]) + delta
		if t >= SET_LIFE:
			_sets.erase(set_)
	for sh: Dictionary in _shells.duplicate():
		_step_shell(sh, delta)


## The pond acre's centre at its land level (`mFI_BkNum2BaseHeight`), not the pond floor.
static func pond_land(mgr: EventManager, block: Vector2i) -> Vector3:
	var center: Vector3 = mgr.cell_position(EventManager.block_unit_to_cell(block, Vector2i(8, 8)))
	var land: float = -INF
	for u: Vector2i in [Vector2i(0, 0), Vector2i(15, 0), Vector2i(0, 15), Vector2i(15, 15)]:
		land = maxf(land, mgr.cell_position(EventManager.block_unit_to_cell(block, u)).y)
	center.y = land
	return center


## `eHanabiSet_SearchNicePos`: between the pond centre and the player, a little back.
func launch_position() -> Vector3:
	var player: Node3D = Player.find(get_tree()) as Node3D if get_tree() != null else null
	var center: Vector3 = pond_center if pond_center != Vector3.INF else global_position
	var at: Vector3 = center
	if player != null:
		at = (center + player.global_position) * 0.5
	at.y = center.y + SET_LIFT
	at.z -= SET_BACK
	return at


func _fire(kind: int) -> void:
	var data: Dictionary = SHELLS[kind]
	var pos: Vector3 = launch_position() + Vector3(_rng.randf_range(-SCATTER, SCATTER), 0.0, _rng.randf_range(-SCATTER, SCATTER))
	var morphs: Array = data["morph"]
	var sh: Dictionary = {
		"kind": kind, "age": 0.0, "scale": 0.01, "pos": pos,
		"morph": morphs[_rng.randi_range(0, morphs.size() - 1)], "tone": _rng.randi_range(0, 1),
	}
	var root := Node3D.new()
	add_child(root)
	root.top_level = true
	sh["node"] = root
	sh["outer"] = _disc(root, data["visual"])
	if not (data["inner"] as Array).is_empty():
		sh["inner"] = _disc(root, data["visual"])
	_shells.append(sh)


func _disc(root: Node3D, visual: StringName) -> Node3D:
	var host := Node3D.new()
	root.add_child(host)
	var paths: PackedStringArray = FieldCatalog.mesh_paths(visual)
	if paths.is_empty():
		return host
	var packed: PackedScene = load(paths[0]) as PackedScene
	if packed == null:
		return host
	var inst: Node = packed.instantiate()
	host.add_child(inst)
	_apply_shader(inst, visual)
	return host


func _apply_shader(node: Node, visual: StringName) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i: int in (mi.mesh.get_surface_count() if mi.mesh != null else 0):
			var mat := ShaderMaterial.new()
			mat.shader = _shader
			var src: Material = mi.get_active_material(i)
			if src is BaseMaterial3D:
				mat.set_shader_parameter("tex", (src as BaseMaterial3D).albedo_texture)
			mat.set_shader_parameter("alpha_from_i", not String(visual).begins_with("ef_hanabi_b"))
			mi.set_surface_override_material(i, mat)
	for child: Node in node.get_children():
		_apply_shader(child, visual)


func _step_shell(sh: Dictionary, delta: float) -> void:
	var data: Dictionary = SHELLS[int(sh["kind"])]
	var life: float = float(data["life"])
	var age: float = float(sh["age"])
	var t: float = age * DecompTime.TICK_HZ
	if t >= life:
		(sh["node"] as Node).queue_free()
		_shells.erase(sh)
		return
	## The flash and the bang go off on the step that reaches their tick.
	var before: float = t - delta * DecompTime.TICK_HZ if age > 0.0 else -1.0
	if before < FLASH_FRAME and t >= FLASH_FRAME:
		var tones: Array = data["light"]
		_flash(tones[mini(int(sh["tone"]), tones.size() - 1)], sh["pos"])
	if before < BANG_FRAME and t >= BANG_FRAME and Audio != null:
		Audio.play_se(data["se"])
	sh["scale"] = Motion.approach(
		float(sh["scale"]), float(data["size"]), EASE_HALF_LIFE, EASE_MAX_SPEED, 0.0, delta
	)
	_draw_shell(sh, data, t, life)
	sh["age"] = age + delta


func _draw_shell(sh: Dictionary, data: Dictionary, t: float, life: float) -> void:
	var age: float = float(sh["age"])
	var spin: float = fposmod(SPIN_RATE * age, 65536.0) / 65536.0 * TAU
	var wobble: float = (sin(fposmod(WOBBLE_RATE * age, 65536.0) / 65536.0 * TAU) + 1.0) * 0.5 * 0.14 + 0.93
	var v2: float = float(sh["scale"]) + adjust(t, 0, life - 1, 0.0, 0.01)
	var s: float = v2 * GX / FieldCatalog.PIPELINE_SCALE
	var drift := Vector3(sin(spin), 0.0, sin(-spin)) * DRIFT
	var root := sh["node"] as Node3D
	root.global_position = (sh["pos"] as Vector3) + drift
	## `RotateX(270)` lays the disc flat; the spin and the wobble stretch act in its plane.
	var basis := Basis(Vector3.UP, spin) * Basis.from_scale(Vector3(wobble, 1.0, 1.0)) * Basis(Vector3.UP, -spin)
	root.basis = basis * Basis(Vector3.RIGHT, deg_to_rad(270.0))
	(sh["outer"] as Node3D).scale = Vector3.ONE * s
	_set_colors(sh["outer"], morph(sh["morph"], t))
	if sh.has("inner"):
		(sh["inner"] as Node3D).scale = Vector3.ONE * s * 0.6
		_set_colors(sh["inner"], morph(data["inner"], t))


func _set_colors(host: Node, m: PackedFloat32Array) -> void:
	var prim := Color(m[0] / 255.0, m[1] / 255.0, m[2] / 255.0, m[3] / 255.0)
	var env := Color(m[5] / 255.0, m[6] / 255.0, m[7] / 255.0, 1.0)
	_set_params(host, prim, env)


func _set_params(node: Node, prim: Color, env: Color) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i: int in (mi.mesh.get_surface_count() if mi.mesh != null else 0):
			var mat := mi.get_surface_override_material(i) as ShaderMaterial
			if mat != null:
				mat.set_shader_parameter("prim", prim)
				mat.set_shader_parameter("env", env)
	for child: Node in node.get_children():
		_set_params(child, prim, env)


## `eEC_MorphCombine` at tick `t` (frames in the tables are halves: `<< 1`).
static func morph(table: Array, t: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(9)
	for i: int in 9:
		var m: Array = table[i]
		if bool(m[2]):
			out[i] = adjust(t, float(int(m[0]) << 1), float(int(m[1]) << 1), float(m[3]), float(m[4]))
		else:
			out[i] = float(m[3])
	return out


## `eEL_CalcAdjust`.
static func adjust(t: float, start: float, end: float, from: float, to: float) -> float:
	if t <= start:
		return from
	if t >= end:
		return to
	return lerpf(from, to, (t - start) / (end - start))


## `regist_effect_light(color, 20, 50)`: the town lights up in the burst's colour.
func _flash(color: Color, at: Vector3) -> void:
	_light_color = color * (4.0 / 3.0 if finale else 1.0)
	_light_left = 50.0 / DecompTime.TICK_HZ
	_light.global_position = at + Vector3(0.0, 6.0, 0.0)


func _update_light(delta: float) -> void:
	if _light_left <= 0.0:
		_light.light_energy = 0.0
		return
	_light_left -= delta
	_light.light_color = Color(_light_color.r, _light_color.g, _light_color.b)
	_light.light_energy = 6.0 * clampf(_light_left / (50.0 / DecompTime.TICK_HZ), 0.0, 1.0)
