class_name FieldParticle
extends GPUParticles3D

## One particle from the effect controller, as a one-shot `GPUParticles3D`
## (`field_particle.tscn`) that frees itself when it is done:
## - puffs: footstep and tumble dust (`ef_dust`, `ef_tumble_dust`), the locomotive's smoke
##   and piston steam (`ef_kisha_kemuri`, `ef_steam`), steam off hot food (`ef_soba_yuge`);
## - splashes kicked up underfoot: sand, water and snow (`ef_sandsplash`, `ef_sibuki`,
##   `ef_yukihane`);
## - drops: water and snow flicked up that splat where they land (`ef_mizutama`,
##   `ef_yukidama`), and the spray off a twirled umbrella (`ef_kasamizutama`);
## - a shovel's dirt (`ef_dig_mud`), and the bobber's splash card and the drops a hooked
##   fish throws up (`ef_turi_hane0` / `1`, `ef_turi_suiteki`).
## `field_particle_motion.gdshader` moves it in closed form and `field_particle.gdshader`
## draws its frames; a `Style` holds the numbers, converted from the decomp's GX-per-tick
## values where they are written.

const SCENE := preload("res://scenes/world/effects/field_particle.tscn")
const GX := FieldCatalog.GX_TO_METERS
const EFFECT_DIR := "res://assets/generated/effects/%s.glb"
const FRAME_DIR := "res://assets/generated/textures/rel/%s.png"
const DUST_FRAMES: Array[String] = ["ef_dust01_0", "ef_dust01_1", "ef_dust01_2", "ef_dust01_3"]
const SMOKE_FRAMES: Array[String] = ["ef_kisha_kemuri01_0", "ef_kisha_kemuri01_1"]
const KINDS: Array[FieldEffects.Kind] = [
	FieldEffects.Kind.DUST, FieldEffects.Kind.TUMBLE_DUST, FieldEffects.Kind.STEAM, FieldEffects.Kind.SOBA_YUGE,
	FieldEffects.Kind.KISHA_KEMURI, FieldEffects.Kind.SAND, FieldEffects.Kind.SIBUKI, FieldEffects.Kind.YUKIHANE,
	FieldEffects.Kind.MIZUTAMA, FieldEffects.Kind.YUKIDAMA, FieldEffects.Kind.KASAMIZUTAMA,
	FieldEffects.Kind.DIG_MUD, FieldEffects.Kind.TURI_HANE, FieldEffects.Kind.TURI_SUITEKI,
]
## `eDig_Mud_*_tex_tbl`: earth, sand and the mole cricket's (`arg1 | 0x8000`) frames.
const MUD_FRAMES: Array[String] = ["ef_anahori02_01_tex", "ef_anahori02_02_tex", "ef_anahori02_03_tex", "ef_anahori02_04_tex"]
const MUD_SAND_FRAMES: Array[String] = ["ef_anahori03_01_tex", "ef_anahori03_02_tex", "ef_anahori03_03_tex", "ef_anahori03_04_tex"]
const MUD_MOLE_FRAMES: Array[String] = ["ef_mogura01_02_tex", "ef_mogura01_03_tex", "ef_mogura01_01_tex", "ef_mogura01_04_tex"]
## `eTH0_ct`: the splash card's scale by arg0.
const HANE_SCALE: Array[float] = [0.01, 0.013, 0.014, 0.009, 0.007]
## `ef_turi_suiteki`: launched at 74.53° from level, 5 GX a tick along it, falling 0.75.
const SUITEKI_ANGLE := 74.53125 * PI / 180.0
## A drop lies where it lands for 14 ticks, playing its splat.
const SPLAT_TIME := 14.0 / 60.0

var kind: FieldEffects.Kind = FieldEffects.Kind.DUST
var _style: Style = null

## Atlas of frames per frame list, built once.
static var _atlases: Dictionary = {}
static var _meshes: Dictionary = {}


## Everything one particle needs, in metres, seconds and 0–1.
class Style:
	var lifetime: float = 0.3
	## Held still this long before it moves (tumble dust).
	var hold: float = 0.0
	var launch: Vector3 = Vector3.ZERO
	var accel: Vector3 = Vector3.ZERO
	var accel_fade: Vector3 = Vector3.ZERO
	var drag: Vector3 = Vector3.ZERO
	var rise_boost: float = 0.0
	var rise_time: float = 0.0
	## Card scale (`Matrix_scale`, GX units) and the window it eases over.
	var size_from_to: Vector2 = Vector2(0.01, 0.01)
	var size_window: Vector2 = Vector2(0.0, 1.0)
	var alpha_from_to: Vector2 = Vector2.ONE
	var alpha_window: Vector2 = Vector2(0.0, 1.0)
	var tint: Color = Color.WHITE
	var model: String = "ef_dust01"
	var frames: Array[String] = DUST_FRAMES
	## Per two-tick step: the two frames, their cross-fade, an alpha and a size multiplier.
	var tile0: PackedInt32Array = PackedInt32Array([0])
	var tile1: PackedInt32Array = PackedInt32Array([0])
	var lods: PackedFloat32Array = PackedFloat32Array([0.0])
	var alphas: PackedFloat32Array = PackedFloat32Array([1.0])
	var sizes: PackedFloat32Array = PackedFloat32Array([1.0])
	## Combiner (see `field_particle.gdshader`), ENV colour, billboard or a fixed lean.
	var mode: int = 1
	var env: Color = Color.BLACK
	var billboard: bool = true
	var tilt: float = 0.0
	## I4 frames (intensity in red) or IA8 (own alpha).
	var intensity_alpha: bool = true
	## Seconds into its motion at which it hits the ground (−1: never).
	var land_time: float = -1.0


static func handles(kind: FieldEffects.Kind) -> bool:
	return KINDS.has(kind)


## Spawns a particle of `kind` at `pos` (metres) facing `yaw`, under `host`. `ground`
## (metres → ground height in metres) is where drops land.
static func spawn(
	host: Node, kind: FieldEffects.Kind, pos: Vector3, yaw: float, a0: int = 0, a1: int = 0,
	ground: Callable = Callable()
) -> FieldParticle:
	if host == null or not handles(kind):
		return null
	var at: Array[Vector3] = [pos]
	var style: Style = style_for(kind, yaw, a0, a1, at, ground)
	var puff := SCENE.instantiate() as FieldParticle
	puff.kind = kind
	host.add_child(puff)
	puff.global_position = at[0]
	puff.apply(style)
	return puff


## The decomp's numbers for `kind` (`*_ct` / `*_mv` / `*_dw`). `at[0]` may be moved for
## kinds that start off the given point.
static func style_for(
	kind: FieldEffects.Kind, yaw: float, a0: int, a1: int, at: Array[Vector3], ground: Callable = Callable()
) -> Style:
	var s := Style.new()
	match kind:
		FieldEffects.Kind.DUST:
			_dust(s, yaw, a1, at)
		FieldEffects.Kind.TUMBLE_DUST:
			_tumble_dust(s, yaw, a1)
		FieldEffects.Kind.STEAM:
			_steam(s, yaw)
		FieldEffects.Kind.SOBA_YUGE:
			_food_steam(s, a0, a1, at)
		FieldEffects.Kind.KISHA_KEMURI:
			_smoke(s, a0, a1, at)
		FieldEffects.Kind.SAND:
			_sand(s, yaw, a0, at)
		FieldEffects.Kind.SIBUKI:
			_splash(s, a0, at)
		FieldEffects.Kind.YUKIHANE:
			_snow_kick(s, at)
		FieldEffects.Kind.MIZUTAMA, FieldEffects.Kind.YUKIDAMA:
			_drop(s, kind, yaw, a1, at, ground)
		FieldEffects.Kind.KASAMIZUTAMA:
			_spray(s, yaw)
		FieldEffects.Kind.DIG_MUD:
			_mud(s, yaw, a0, a1)
		FieldEffects.Kind.TURI_HANE:
			_hane(s, a0, a1)
		FieldEffects.Kind.TURI_SUITEKI:
			_suiteki(s, a0, a1)
	_even(s)
	return s


## Where a puff in `style` is, relative to its start, `t` seconds in (the motion shader's
## path, for tests).
static func offset_at(style: Style, t: float) -> Vector3:
	var u: float = maxf(t - style.hold, 0.0)
	if style.land_time >= 0.0:
		u = minf(u, style.land_time)
	var out := Vector3(
		_axis(style.launch.x, style.accel.x, style.drag.x, style.accel_fade.x, u),
		_axis(style.launch.y, style.accel.y, style.drag.y, style.accel_fade.y, u),
		_axis(style.launch.z, style.accel.z, style.drag.z, style.accel_fade.z, u))
	if style.rise_time > 0.0:
		var r: float = minf(u, style.rise_time)
		out.y += style.rise_boost * (r - r * r / (2.0 * style.rise_time))
	return out


static func _reach(k: float, t: float) -> float:
	return t if k < 1e-5 else (1.0 - exp(-k * t)) / k


static func _axis(v0: float, a0: float, k: float, ka: float, t: float) -> float:
	if absf(k - ka) < 1e-4:
		if k < 1e-5:
			return v0 * t + 0.5 * a0 * t * t
		return v0 * _reach(k, t) + a0 * (1.0 - exp(-k * t) * (1.0 + k * t)) / (k * k)
	var a: float = a0 / (k - ka)
	return (v0 - a) * _reach(k, t) + a * _reach(ka, t)


## Where it ends up relative to where it started (a fishing drop's fall back to the water).
func landed_offset() -> Vector3:
	return offset_at(_style, _style.lifetime) if _style != null else Vector3.ZERO


## Hands `style` to the shaders and starts the puff.
func apply(style: Style) -> void:
	_style = style
	lifetime = style.lifetime + style.hold
	var motion := (process_material as ShaderMaterial).duplicate() as ShaderMaterial
	var scale_k: float = GX / FieldCatalog.PIPELINE_SCALE
	motion.set_shader_parameter("launch", style.launch)
	motion.set_shader_parameter("accel", style.accel)
	motion.set_shader_parameter("accel_fade", style.accel_fade)
	motion.set_shader_parameter("drag", style.drag)
	motion.set_shader_parameter("rise_boost", style.rise_boost)
	motion.set_shader_parameter("rise_time", style.rise_time)
	motion.set_shader_parameter("hold", style.hold)
	motion.set_shader_parameter("size_from_to", style.size_from_to * scale_k)
	motion.set_shader_parameter("size_window", style.size_window)
	motion.set_shader_parameter("alpha_from_to", style.alpha_from_to * style.tint.a)
	motion.set_shader_parameter("alpha_window", style.alpha_window)
	motion.set_shader_parameter("tint", Vector3(style.tint.r, style.tint.g, style.tint.b))
	motion.set_shader_parameter("land_time", style.land_time)
	motion.set_shader_parameter("tilt", 0.0 if style.billboard else style.tilt)
	process_material = motion
	var card := draw_pass_1
	var mat := ((card as PrimitiveMesh).material if card is PrimitiveMesh else null) as ShaderMaterial
	if mat != null:
		mat = mat.duplicate() as ShaderMaterial
		mat.set_shader_parameter("frames", _atlas(style.frames))
		mat.set_shader_parameter("frame_count", style.frames.size())
		mat.set_shader_parameter("steps", style.tile0.size())
		mat.set_shader_parameter("tile0", _pad_ints(style.tile0))
		mat.set_shader_parameter("tile1", _pad_ints(style.tile1))
		mat.set_shader_parameter("lods", _pad_floats(style.lods))
		mat.set_shader_parameter("alphas", _pad_floats(style.alphas))
		mat.set_shader_parameter("sizes", _pad_floats(style.sizes))
		mat.set_shader_parameter("land_time", style.land_time)
		mat.set_shader_parameter("mode", style.mode)
		mat.set_shader_parameter("env", Vector3(style.env.r, style.env.g, style.env.b))
		mat.set_shader_parameter("billboard", style.billboard)
		mat.set_shader_parameter("intensity_alpha", style.intensity_alpha)
		mat.set_shader_parameter("hold", style.hold)
		var mesh: Mesh = _mesh(style.model)
		if mesh != null:
			mesh = mesh.duplicate() as Mesh
			for i: int in mesh.get_surface_count():
				mesh.surface_set_material(i, mat)
			draw_pass_1 = mesh
		else:
			(card as PrimitiveMesh).material = mat
	finished.connect(queue_free)
	emitting = true


## The draw shader's tables hold `STEPS_MAX` entries.
const STEPS_MAX := 24


static func _pad_ints(values: PackedInt32Array) -> PackedInt32Array:
	var out := values.duplicate()
	out.resize(STEPS_MAX)
	return out


static func _pad_floats(values: PackedFloat32Array) -> PackedFloat32Array:
	var out := values.duplicate()
	out.resize(STEPS_MAX)
	return out


# --- the kinds ---------------------------------------------------------------------------

static func _speed(gx_per_tick: Vector3) -> Vector3:
	return gx_per_tick * GX * 60.0


static func _accel(gx_per_tick2: Vector3) -> Vector3:
	return gx_per_tick2 * GX * 3600.0


## Drag rate (1/s) for a velocity multiplied by `factor` every tick.
static func _drag(factor: float) -> float:
	return -log(factor) * 60.0


static func _ticks(n: float) -> float:
	return n / 60.0


## `eDT_ct` / `eDT_mv` / `eDT_dw`: arg1 picks the push and size; 18 ticks.
static func _dust(s: Style, yaw: float, arg1: int, at: Array[Vector3]) -> void:
	var v := Vector3(0.0, 1.0 if arg1 != 4 else 0.0, 0.25)
	match arg1:
		8:
			v.z = -2.0
		1:
			v.z = -1.5
		2:
			v.z = -1.0
		3, 5:
			v.z = 0.0
		0:
			v.z = 0.5
			at[0] += Vector3(15.0 * sin(yaw), -15.0, 15.0 * cos(yaw)) * GX
		9:
			v.z = 0.75
			at[0] += Vector3(25.0 * sin(yaw), 0.0, 25.0 * cos(yaw)) * GX
		4:
			at[0].y += 5.0 * GX
	var a := Vector3(0.0, -0.05, 0.075)
	if arg1 == 4:
		a = Vector3(0.0, 0.1, 0.0)
	elif arg1 == 0:
		a = Vector3.ZERO
	var size := 0.01
	if arg1 == 4:
		size = 0.015
	elif arg1 == 0 or arg1 == 9:
		size = 0.007
	s.lifetime = _ticks(18)
	s.launch = _speed(FieldEffects.rot_y(v, yaw))
	s.accel = _accel(FieldEffects.rot_y(a, yaw))
	if arg1 == 0 or arg1 == 9:
		s.drag = Vector3.ONE * _drag(sqrt(0.85))
	s.size_from_to = Vector2(size, size)
	s.tint = FieldEffects.DUST_PRIM[arg1] if arg1 >= 0 and arg1 < FieldEffects.DUST_PRIM.size() else Color.WHITE
	_tiles(s, FieldEffects.DUST_TILES, FieldEffects.DUST_LOD)
	s.alphas = PackedFloat32Array()
	for alpha: int in FieldEffects.DUST_ALPHA:
		s.alphas.append(alpha / 255.0)


## `eTDT_*`: thrown forward and up, braking hard; it waits the first few ticks of a life
## longer than 30 before it moves.
static func _tumble_dust(s: Style, yaw: float, arg1: int) -> void:
	var z := 3.5
	match arg1:
		1:
			z = 3.75
		5, 7, 6, 8:
			z = 5.5
		9:
			z = 3.0
	var life := 30
	if arg1 == 1 or arg1 == 3:
		life = 32
	elif arg1 == 0 or arg1 == 4:
		life = 34
	elif arg1 == 7 or arg1 == 8:
		life = 36
	s.lifetime = _ticks(30)
	s.hold = _ticks(life - 30)
	s.launch = _speed(FieldEffects.rot_y(Vector3(0.0, 0.5, z), yaw))
	s.accel = _accel(FieldEffects.rot_y(Vector3(0.0, 0.05, -0.05), yaw))
	s.accel_fade = Vector3(0.0, _drag(sqrt(0.8)), 0.0)
	s.drag = Vector3(_drag(sqrt(0.8)), _drag(sqrt(0.95)), _drag(sqrt(0.8)))
	s.size_from_to = Vector2(0.005, 0.02 if arg1 in [1, 5, 6] else 0.015)
	s.size_window = Vector2(0.0, _ticks(30))
	s.alpha_from_to = Vector2(1.0, 120.0 / 255.0)
	s.alpha_window = Vector2(_ticks(8), _ticks(30))
	_tiles(s, FieldEffects.TDUST_TILES, FieldEffects.TDUST_LOD)


## `eSteam_*`: the piston puffs out along its heading at 0.5–1.5 and 1.5–4.5 down, rising
## back, growing over its 30 ticks.
static func _steam(s: Style, yaw: float) -> void:
	var speed: float = randf() + 0.5
	s.lifetime = _ticks(30)
	s.launch = _speed(Vector3(sin(yaw) * speed, -randf() * 3.0 - 1.5, cos(yaw) * speed))
	s.accel = _accel(Vector3(0.0, 0.125, 0.0))
	s.drag = Vector3.ONE * _drag(sqrt(0.8))
	s.size_from_to = Vector2(0.005, 0.02)
	s.size_window = Vector2(0.0, _ticks(30))
	_tiles(s, FieldEffects.STEAM_TILES, FieldEffects.STEAM_LOD)


## `eSoba_Yuge_*`: 1 GX up and `arg0` out on a random heading, rising slowly; grows and
## thins over 44 ticks, warmer and denser for the stew (`arg1`).
static func _food_steam(s: Style, arg0: int, arg1: int, at: Array[Vector3]) -> void:
	var heading: float = randf() * TAU
	at[0] += Vector3(float(arg0) * sin(heading), 1.0, float(arg0) * cos(heading)) * GX
	s.lifetime = _ticks(44)
	s.accel = _accel(Vector3(0.0, 0.017, 0.0))
	s.drag = Vector3(0.0, _drag(0.95), 0.0)
	s.size_from_to = Vector2(0.001, 0.005 if arg1 == 0 else 0.01)
	s.size_window = Vector2(0.0, _ticks(44))
	s.alpha_from_to = Vector2((130.0 if arg1 == 0 else 190.0) / 255.0, 10.0 / 255.0)
	s.alpha_window = Vector2(0.0, _ticks(44))
	s.tint = Color.WHITE if arg1 == 0 else Color8(255, 200, 130)
	_tiles(s, FieldEffects.YUGE_TILES, FieldEffects.YUGE_LOD)


## `eKishaK_*`: ±2.5 GX of jitter; climbs 2.2 GX a tick easing to 0.5 over the first 20,
## drifting with the train (`arg0 == 1`); swells over 40 ticks and fades over the last 40.
static func _smoke(s: Style, arg0: int, arg1: int, at: Array[Vector3]) -> void:
	at[0] += Vector3(randf() * 5.0 - 2.5, 0.0, randf() * 5.0 - 2.5) * GX
	var drift := Vector3.ZERO
	if arg0 == 1:
		var angle: float = float(arg1) * MathUtil.S16
		drift = Vector3(sin(angle) * 0.2, 0.0, cos(angle) * 0.2)
	s.lifetime = _ticks(80)
	s.launch = _speed(drift + Vector3(0.0, 0.5, 0.0))
	s.rise_boost = (2.2 - 0.5) * GX * 60.0
	s.rise_time = _ticks(20)
	s.size_from_to = Vector2(0.003, 0.027)
	s.size_window = Vector2(0.0, _ticks(40))
	s.alpha_from_to = Vector2(200.0 / 255.0, 4.0 / 255.0)
	s.alpha_window = Vector2(_ticks(40), _ticks(80))
	s.tint = FieldEffects.KEMURI_PRIM
	s.model = "ef_kisha_kemuri01"
	s.frames = SMOKE_FRAMES
	s.tile0 = PackedInt32Array([0])
	s.tile1 = PackedInt32Array([1])
	s.lods = PackedFloat32Array([FieldEffects.KEMURI_LOD])
	s.alphas = PackedFloat32Array([1.0])


static func _tiles(s: Style, tiles: Array[Vector2i], lods: Array[int]) -> void:
	s.tile0 = PackedInt32Array()
	s.tile1 = PackedInt32Array()
	s.lods = PackedFloat32Array()
	s.alphas = PackedFloat32Array()
	for i: int in tiles.size():
		s.tile0.append(tiles[i].x)
		s.tile1.append(tiles[i].y)
		s.lods.append(lods[i] / 255.0 if i < lods.size() else 0.0)
		s.alphas.append(1.0)


## Every step table as long as the longest, the shorter ones holding their last value.
static func _even(s: Style) -> void:
	var n: int = maxi(maxi(s.tile0.size(), s.tile1.size()), maxi(maxi(s.lods.size(), s.alphas.size()), s.sizes.size()))
	s.tile0 = _hold_ints(s.tile0, n)
	s.tile1 = _hold_ints(s.tile1, n)
	s.lods = _hold_floats(s.lods, n, 0.0)
	s.alphas = _hold_floats(s.alphas, n, 1.0)
	s.sizes = _hold_floats(s.sizes, n, 1.0)


static func _hold_ints(values: PackedInt32Array, n: int) -> PackedInt32Array:
	var out := values.duplicate()
	var last: int = out[out.size() - 1] if not out.is_empty() else 0
	while out.size() < n:
		out.append(last)
	return out


static func _hold_floats(values: PackedFloat32Array, n: int, fallback: float) -> PackedFloat32Array:
	var out := values.duplicate()
	var last: float = out[out.size() - 1] if not out.is_empty() else fallback
	while out.size() < n:
		out.append(last)
	return out


## Frame per two-tick step that advances every other step: 0, 0, 1, 1, … to `last`.
static func _every_other(steps: int, last: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i: int in steps:
		out.append(mini(i >> 1, last))
	return out


static func _numbered(pattern: String, from: int, to: int) -> Array[String]:
	var out: Array[String] = []
	for i: int in range(from, to + 1):
		out.append(pattern % i)
	return out


## `eSandsplash_*` (arg0 picks the throw): a lean card of sand thrown off the step, 16 ticks.
static func _sand(s: Style, yaw: float, arg0: int, at: Array[Vector3]) -> void:
	at[0] += Vector3(0.0, -3.0, 5.0) * GX
	var v := Vector3(0.0, 0.5, 0.0)
	var a := Vector3(0.0, -0.01, 0.0)
	if arg0 == 2:
		v = Vector3(sin(yaw), 0.5, cos(yaw))
		a = Vector3.ZERO
	elif arg0 == 1:
		v = Vector3(sin(yaw), 0.5, cos(yaw))
		a = Vector3(0.0, -0.075, 0.0)
	elif arg0 == 3:
		v = Vector3(sin(yaw) * 0.25, 0.0, cos(yaw))
		a = Vector3(0.0, -0.05, 0.0)
	s.lifetime = _ticks(16)
	s.launch = _speed(v)
	s.accel = _accel(a)
	_ground_card(s, "ef_sunahane01_00", _numbered("ef_sunahane01_%d_inta_ia8", 0, 3), deg_to_rad(-45.0), 8)
	s.intensity_alpha = false
	s.mode = 3
	s.tint = Color8(20, 20, 20, 255)
	s.env = Color8(205, 180, 140, 255)


## `eSibuki_*`: a splash of water at the foot, shown from its third step, 12 ticks.
static func _splash(s: Style, arg0: int, at: Array[Vector3]) -> void:
	at[0] += Vector3(0.0, -3.0, 5.0) * GX
	s.lifetime = _ticks(12)
	s.billboard = false
	s.tilt = deg_to_rad(-30.0)
	s.model = "ef_sibuki01_00"
	s.frames = _numbered("ef_sibuki01_%d_int_i4", 1, 4)
	s.tile0 = PackedInt32Array([0, 0, 0, 1, 2, 3])
	s.tile1 = s.tile0
	s.lods = PackedFloat32Array([0.0])
	s.alphas = PackedFloat32Array([0.0, 0.0, 1.0])
	s.size_from_to = Vector2(0.011, 0.011)
	s.mode = 0
	s.tint = Color8(200, 255, 255, 155 if arg0 == 0 else 235)


## `eYukihane_*`: a kick of snow, rising a little and falling back, 16 ticks.
static func _snow_kick(s: Style, at: Array[Vector3]) -> void:
	at[0].y += 0.5 * GX
	s.lifetime = _ticks(16)
	s.launch = _speed(Vector3(0.0, 0.5, 0.0))
	s.accel = _accel(Vector3(0.0, -0.02, 0.0))
	_ground_card(s, "ef_yukihane01_00", _numbered("ef_yukihane01_%d_inta_ia8", 0, 3), deg_to_rad(-45.0), 8)
	s.size_from_to = Vector2(0.008, 0.008)
	s.intensity_alpha = false
	s.mode = 2
	s.tint = Color8(50, 80, 120, 230)


static func _ground_card(s: Style, model: String, frames: Array[String], tilt: float, steps: int) -> void:
	s.billboard = false
	s.tilt = tilt
	s.model = model
	s.frames = frames
	s.tile0 = _every_other(steps, frames.size() - 1)
	s.tile1 = s.tile0
	s.lods = PackedFloat32Array([0.0])
	s.alphas = PackedFloat32Array([1.0])


## `eMizutama_ct` / `eYukidama_ct`: flicked up off the step (arg1 = speed set << 12 | the
## direction), it flies until it reaches the ground 3 GX above where it started, then lies
## there splatting for 14 ticks. 50 ticks at most.
static func _drop(s: Style, kind: FieldEffects.Kind, yaw: float, arg1: int, at: Array[Vector3], ground: Callable) -> void:
	var water: bool = kind == FieldEffects.Kind.MIZUTAMA
	var speeds: Array[Vector4] = FieldEffects.MIZU_SPEED if water else FieldEffects.YUKI_SPEED
	var speed_set: int = clampi((arg1 >> 12) & 0xF, 0, speeds.size() - 1)
	var dir_index: int = arg1 & 0x0FFF
	var sp: Vector4 = speeds[speed_set]
	var v := Vector3(0.0, sp.x + randf() * sp.y, sp.z)
	var dir: float
	if water:
		dir = yaw + MathUtil.s16_to_rad(FieldEffects.MIZU_ANGLE[clampi(dir_index, 0, FieldEffects.MIZU_ANGLE.size() - 1)])
	else:
		dir = yaw + deg_to_rad(FieldEffects.YUKI_ANGLE_DEG[clampi(dir_index, 0, FieldEffects.YUKI_ANGLE_DEG.size() - 1)])
	v = FieldEffects.rot_y(v, dir)
	v.x += sin(yaw) * sp.w
	v.z += cos(yaw) * sp.w
	at[0] += Vector3((randf() - 0.5) * 6.0, 0.0, (randf() - 0.5) * 6.0) * GX
	s.launch = _speed(v)
	s.accel = _accel(Vector3(0.0, -0.375 if water else -0.3, 0.0))
	## It lands on the ground 3 GX up (`offset.y = ground + 3`).
	var floor_y: float = at[0].y
	if ground.is_valid():
		var g: float = float(ground.call(at[0]))
		if g > FieldCollision.NO_FLOOR + 1.0:
			floor_y = g
	s.land_time = _landing(s.launch.y, s.accel.y, at[0].y - (floor_y + 3.0 * GX))
	s.lifetime = minf(_ticks(50), s.land_time + SPLAT_TIME) if s.land_time >= 0.0 else _ticks(50)
	s.model = "ef_koke_suiteki01_00" if water else "ef_koke_yuki01_00"
	s.frames = _numbered("ef_koke_suiteki01_%d_int_i4", 0, 3) if water else _numbered("ef_koke_yuki01_%d_inta_ia8", 0, 3)
	s.tile0 = _every_other(7, 3)
	s.tile1 = s.tile0
	s.lods = PackedFloat32Array([0.0])
	if water:
		s.size_from_to = Vector2(0.008, 0.004)
		s.size_window = Vector2(_ticks(10), _ticks(50))
		s.mode = 0
		s.tint = Color8(200, 255, 255, 200)
	else:
		s.size_from_to = Vector2(0.007, 0.0035)
		s.size_window = Vector2(_ticks(20), _ticks(40))
		s.mode = 2
		s.intensity_alpha = false
		s.tint = Color8(100, 160, 240, 255)


## When something launched upward at `vy` under `ay` (< 0), starting `height` above the ground,
## comes down to it; −1 if it never does.
static func _landing(vy: float, ay: float, height: float) -> float:
	if ay >= 0.0:
		return -1.0
	## height + vy·t + ½·ay·t² = 0, the later root.
	var disc: float = vy * vy - 2.0 * ay * height
	if disc < 0.0:
		return -1.0
	return maxf((-vy - sqrt(disc)) / ay, 0.0)


## `eKasamizutama_ct`: flung out 2.5 GX a tick, 45–90° off straight up about a random
## heading, the whole fan leaning 45° back from the player's facing; swells and shrinks by
## `eKasamizutama_scale_table` over 20 ticks.
static func _spray(s: Style, yaw: float) -> void:
	var lean: float = deg_to_rad(45.0 + randf() * 45.0)
	var heading: float = randf() * TAU
	var v := Vector3(2.5 * sin(lean) * sin(heading), 2.5 * cos(lean), 2.5 * sin(lean) * cos(heading))
	s.lifetime = _ticks(20)
	s.launch = _speed(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(-45.0)) * v)
	s.accel = _accel(Vector3(0.0, -0.105, 0.0))
	s.model = "ef_koke_suiteki01_00"
	s.frames = ["ef_koke_suiteki01_0_int_i4"]
	s.tile0 = PackedInt32Array([0])
	s.tile1 = s.tile0
	s.lods = PackedFloat32Array([0.0])
	s.sizes = PackedFloat32Array(FieldEffects.KASAMIZUTAMA_SCALE)
	s.size_from_to = Vector2(0.005, 0.005)
	s.mode = 0
	s.tint = Color8(200, 255, 255, 200)


## `eDig_Mud_ct` / `_mv` / `_dw`: a clot of dirt (arg0 the ground attribute). arg1 0–2:
## flung back 3.5 GX a tick (±1.1) at 50–70° below level, 20–40° off the facing; 3–5: out
## 0.4 at 120°·arg1, up 1.75–2.75; 6 and 7: out 1 along the facing, up 2–3; 8 (a weed):
## straight up 2–3. All fall 0.175. 32 / 30 / 28 ticks; four frames by what is left
## (over 18, 14, 10). `| 0x4000` is half size, `| 0x8000` the mole cricket's dirt.
static func _mud(s: Style, yaw: float, arg0: int, arg1: int) -> void:
	var mole: bool = (arg1 & 0x8000) != 0
	var small: bool = (arg1 & 0x4000) != 0
	var which: int = arg1 & 0x3FFF
	var life: int = 28
	if which == 0 or which == 3:
		life = 32
	elif which == 1 or which == 4:
		life = 30
	var v := Vector3.ZERO
	if which < 3:
		var pitch: float = deg_to_rad(-60.0 + (randf() * 20.0 - 10.0))
		var speed: float = -3.5 + (randf() * 4.5 - 2.25) * 0.5
		var heading: float = yaw + deg_to_rad(30.0 + (randf() * 20.0 - 10.0))
		v = Vector3(speed * cos(pitch) * sin(heading), speed * sin(pitch), speed * cos(pitch) * cos(heading))
	elif which < 6:
		var heading: float = yaw + deg_to_rad(120.0 * which)
		v = Vector3(0.4 * sin(heading), 1.75 + randf(), 0.4 * cos(heading))
	elif which != 8:
		v = Vector3(sin(yaw), 2.0 + randf(), cos(yaw))
	else:
		v = Vector3(0.0, 2.0 + randf(), 0.0)
	var a := Vector3(0.0, -0.175, 0.0)
	s.lifetime = _ticks(life)
	## `v += a; p += v` a tick is the continuous path launched half a step faster.
	s.launch = _speed(v + a * 0.5)
	s.accel = _accel(a)
	var size: float = 0.005 if small else 0.01
	s.size_from_to = Vector2(size, size)
	s.model = "ef_mogura01_00" if mole else ("ef_anahori03_00" if arg0 == FootstepEffects.ATTR_SAND or arg0 == FootstepEffects.ATTR_WAVE else "ef_anahori02_00")
	s.frames = MUD_MOLE_FRAMES if mole else (MUD_SAND_FRAMES if s.model == "ef_anahori03_00" else MUD_FRAMES)
	s.tile0 = PackedInt32Array()
	for step: int in life / 2:
		var left: int = life - step * 2
		s.tile0.append(0 if left > 18 else (1 if left > 14 else (2 if left > 10 else 3)))
	s.tile1 = s.tile0
	s.lods = PackedFloat32Array([0.0])
	s.mode = 4
	s.intensity_alpha = false


## `eTH0_*` / `eTH1_*`: the bobber's splash, standing up out of the water, 16 ticks, each
## of its four frames held four. arg1 0 is `ef_turi_hane01` (scale by arg0), 1 is
## `ef_turi_hane02`.
static func _hane(s: Style, arg0: int, arg1: int) -> void:
	s.lifetime = _ticks(16)
	s.billboard = false
	var big: bool = arg1 == 1
	s.model = "ef_turi_hane02_00" if big else "ef_turi_hane01_00"
	s.frames = _numbered("ef_turi_hane02_%d_int_i4", 0, 3) if big else _numbered("ef_turi_hane01_%d_int_i4", 0, 3)
	s.tile0 = PackedInt32Array([0, 0, 1, 1, 2, 2, 3, 3])
	s.tile1 = s.tile0
	s.lods = PackedFloat32Array([0.0])
	var size: float = 0.01 if big else HANE_SCALE[clampi(arg0, 0, HANE_SCALE.size() - 1)]
	s.size_from_to = Vector2(size, size)
	s.mode = 0
	s.tint = Color.WHITE


## `eTS_ct` / `_dw`: one of `arg1` drops thrown up round a circle (this is drop `arg0`),
## 0–5 GX a tick out; it ends when it is back down at the water (a ring there is the
## router's job, `FootstepEffects.bobber_splash`).
static func _suiteki(s: Style, arg0: int, arg1: int) -> void:
	var heading: float = deg_to_rad(float(arg0) * 360.0 / float(arg1)) if arg1 != 0 else 0.0
	var reach: float = randf() * 5.0
	var flat: float = reach * cos(SUITEKI_ANGLE)
	s.launch = _speed(Vector3(flat * sin(heading), 5.0 * sin(SUITEKI_ANGLE), flat * cos(heading)))
	s.accel = _accel(Vector3(0.0, -0.75, 0.0))
	s.lifetime = suiteki_flight()
	s.model = "ef_turi_suiteki01_00"
	s.frames = ["ef_turi_suiteki01_0"]
	s.tile0 = PackedInt32Array([0])
	s.tile1 = s.tile0
	s.lods = PackedFloat32Array([0.0])
	s.size_from_to = Vector2(0.0015, 0.0015)
	s.mode = 4
	s.intensity_alpha = false


## Seconds a fishing drop is up before it falls back to the water it left.
static func suiteki_flight() -> float:
	return _ticks(2.0 * 5.0 * sin(SUITEKI_ANGLE) / 0.75)


# --- art ---------------------------------------------------------------------------------

## The frames side by side in one texture, so a shader can pick one by number.
static func _atlas(names: Array[String]) -> Texture2D:
	var key: String = ",".join(names)
	if _atlases.has(key):
		return _atlases[key]
	var images: Array[Image] = []
	for name: String in names:
		var path := FRAME_DIR % name
		if not ResourceLoader.exists(path):
			continue
		var img: Image = (load(path) as Texture2D).get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		images.append(img)
	var tex: Texture2D = null
	if images.is_empty():
		var blank := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		blank.fill(Color(0.6, 0.6, 0.6, 1.0))
		tex = ImageTexture.create_from_image(blank)
	else:
		var w: int = images[0].get_width()
		var h: int = images[0].get_height()
		var atlas := Image.create(w * names.size(), h, false, Image.FORMAT_RGBA8)
		for i: int in images.size():
			var img: Image = images[i]
			if img.get_width() != w or img.get_height() != h:
				img.resize(w, h)
			atlas.blit_rect(img, Rect2i(0, 0, w, h), Vector2i(w * i, 0))
		tex = ImageTexture.create_from_image(atlas)
	_atlases[key] = tex
	return tex


static func _mesh(model: String) -> Mesh:
	if _meshes.has(model):
		return _meshes[model]
	var mesh: Mesh = null
	var path := EFFECT_DIR % model
	if ResourceLoader.exists(path):
		var inst: Node = (load(path) as PackedScene).instantiate()
		for node: Node in inst.find_children("*", "MeshInstance3D", true, false):
			mesh = (node as MeshInstance3D).mesh
			break
		inst.free()
	_meshes[model] = mesh
	return mesh
