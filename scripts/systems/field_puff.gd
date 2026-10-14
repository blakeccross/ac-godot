class_name FieldPuff
extends GPUParticles3D

## A puff of dust, steam or smoke from the effect controller: footstep and tumble dust
## (`ef_dust`, `ef_tumble_dust`), the locomotive's smoke and piston steam (`ef_kisha_kemuri`,
## `ef_steam`) and the steam off hot food (`ef_soba_yuge`). Each is a one-shot
## `GPUParticles3D` (`field_puff.tscn`) that frees itself when its puff has faded.
## `field_puff_motion.gdshader` moves it in closed form and `field_puff.gdshader` draws its
## cross-faded frames; a `Style` holds the numbers, converted from the decomp's GX-per-tick
## values where they are written.

const SCENE := preload("res://scenes/world/effects/field_puff.tscn")
const GX := FieldCatalog.GX_TO_METERS
const EFFECT_DIR := "res://assets/generated/effects/%s.glb"
const FRAME_DIR := "res://assets/generated/textures/rel/%s.png"
const DUST_FRAMES: Array[String] = ["ef_dust01_0", "ef_dust01_1", "ef_dust01_2", "ef_dust01_3"]
const SMOKE_FRAMES: Array[String] = ["ef_kisha_kemuri01_0", "ef_kisha_kemuri01_1"]
const KINDS: Array[FieldFx.Kind] = [
	FieldFx.Kind.DUST, FieldFx.Kind.TUMBLE_DUST, FieldFx.Kind.STEAM, FieldFx.Kind.SOBA_YUGE,
	FieldFx.Kind.KISHA_KEMURI,
]

var kind: FieldFx.Kind = FieldFx.Kind.DUST

## Atlas of frames per frame list, built once.
static var _atlases: Dictionary = {}
static var _meshes: Dictionary = {}


## Everything one puff needs, in metres, seconds and 0–1.
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
	## Per two-tick step: the two frames, their cross-fade and an alpha multiplier.
	var tile0: PackedInt32Array = PackedInt32Array([0])
	var tile1: PackedInt32Array = PackedInt32Array([0])
	var lods: PackedFloat32Array = PackedFloat32Array([0.0])
	var alphas: PackedFloat32Array = PackedFloat32Array([1.0])


static func handles(kind: FieldFx.Kind) -> bool:
	return KINDS.has(kind)


## Spawns a puff of `kind` at `pos` (metres) facing `yaw`, under `host`.
static func spawn(host: Node, kind: FieldFx.Kind, pos: Vector3, yaw: float, a0: int = 0, a1: int = 0) -> FieldPuff:
	if host == null or not handles(kind):
		return null
	var at: Array[Vector3] = [pos]
	var style: Style = style_for(kind, yaw, a0, a1, at)
	var puff := SCENE.instantiate() as FieldPuff
	puff.kind = kind
	host.add_child(puff)
	puff.global_position = at[0]
	puff.apply(style)
	return puff


## The decomp's numbers for `kind` (`*_ct` / `*_mv` / `*_dw`). `at[0]` may be moved for
## kinds that start off the given point.
static func style_for(kind: FieldFx.Kind, yaw: float, a0: int, a1: int, at: Array[Vector3]) -> Style:
	var s := Style.new()
	match kind:
		FieldFx.Kind.DUST:
			_dust(s, yaw, a1, at)
		FieldFx.Kind.TUMBLE_DUST:
			_tumble_dust(s, yaw, a1)
		FieldFx.Kind.STEAM:
			_steam(s, yaw)
		FieldFx.Kind.SOBA_YUGE:
			_food_steam(s, a0, a1, at)
		FieldFx.Kind.KISHA_KEMURI:
			_smoke(s, a0, a1, at)
	return s


## Where a puff in `style` is, relative to its start, `t` seconds in (the motion shader's
## path, for tests).
static func offset_at(style: Style, t: float) -> Vector3:
	var u: float = maxf(t - style.hold, 0.0)
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


## Hands `style` to the shaders and starts the puff.
func apply(style: Style) -> void:
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
	motion.set_shader_parameter("alpha_from_to", style.alpha_from_to)
	motion.set_shader_parameter("alpha_window", style.alpha_window)
	motion.set_shader_parameter("tint", Vector3(style.tint.r, style.tint.g, style.tint.b))
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
	s.launch = _speed(FieldFx.rot_y(v, yaw))
	s.accel = _accel(FieldFx.rot_y(a, yaw))
	if arg1 == 0 or arg1 == 9:
		s.drag = Vector3.ONE * _drag(sqrt(0.85))
	s.size_from_to = Vector2(size, size)
	s.tint = FieldFx.DUST_PRIM[arg1] if arg1 >= 0 and arg1 < FieldFx.DUST_PRIM.size() else Color.WHITE
	_tiles(s, FieldFx.DUST_TILES, FieldFx.DUST_LOD)
	s.alphas = PackedFloat32Array()
	for alpha: int in FieldFx.DUST_ALPHA:
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
	s.launch = _speed(FieldFx.rot_y(Vector3(0.0, 0.5, z), yaw))
	s.accel = _accel(FieldFx.rot_y(Vector3(0.0, 0.05, -0.05), yaw))
	s.accel_fade = Vector3(0.0, _drag(sqrt(0.8)), 0.0)
	s.drag = Vector3(_drag(sqrt(0.8)), _drag(sqrt(0.95)), _drag(sqrt(0.8)))
	s.size_from_to = Vector2(0.005, 0.02 if arg1 in [1, 5, 6] else 0.015)
	s.size_window = Vector2(0.0, _ticks(30))
	s.alpha_from_to = Vector2(1.0, 120.0 / 255.0)
	s.alpha_window = Vector2(_ticks(8), _ticks(30))
	_tiles(s, FieldFx.TDUST_TILES, FieldFx.TDUST_LOD)


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
	_tiles(s, FieldFx.STEAM_TILES, FieldFx.STEAM_LOD)


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
	_tiles(s, FieldFx.YUGE_TILES, FieldFx.YUGE_LOD)


## `eKishaK_*`: ±2.5 GX of jitter; climbs 2.2 GX a tick easing to 0.5 over the first 20,
## drifting with the train (`arg0 == 1`); swells over 40 ticks and fades over the last 40.
static func _smoke(s: Style, arg0: int, arg1: int, at: Array[Vector3]) -> void:
	at[0] += Vector3(randf() * 5.0 - 2.5, 0.0, randf() * 5.0 - 2.5) * GX
	var drift := Vector3.ZERO
	if arg0 == 1:
		var angle: float = float(arg1) * MLib.S16
		drift = Vector3(sin(angle) * 0.2, 0.0, cos(angle) * 0.2)
	s.lifetime = _ticks(80)
	s.launch = _speed(drift + Vector3(0.0, 0.5, 0.0))
	s.rise_boost = (2.2 - 0.5) * GX * 60.0
	s.rise_time = _ticks(20)
	s.size_from_to = Vector2(0.003, 0.027)
	s.size_window = Vector2(0.0, _ticks(40))
	s.alpha_from_to = Vector2(200.0 / 255.0, 4.0 / 255.0)
	s.alpha_window = Vector2(_ticks(40), _ticks(80))
	s.tint = FieldFx.KEMURI_PRIM
	s.model = "ef_kisha_kemuri01"
	s.frames = SMOKE_FRAMES
	s.tile0 = PackedInt32Array([0])
	s.tile1 = PackedInt32Array([1])
	s.lods = PackedFloat32Array([FieldFx.KEMURI_LOD])
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
