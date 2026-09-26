class_name FieldFx
extends Node3D

## One effect-controller particle for the player's step / skid / tumble effects:
## `ef_dust`, `ef_tumble_dust`, `ef_sandsplash`, `ef_mizutama`, `ef_yukidama`,
## `ef_yukihane`, `ef_sibuki`, `ef_hanabira`, `ef_turn_footprint`, `ef_tumble_bodyprint`,
## and the locomotive's `ef_kisha_kemuri` (smoke) / `ef_steam` (piston steam).
## Each ticks at the controller's 60 Hz: `*_mv`, then `timer--`, dead at 0. State is GX
## (40 GX = 2 m); the node itself lives in metres. `StepFx` decides which to spawn.

enum Kind {
	DUST, TUMBLE_DUST, SAND, MIZUTAMA, YUKIDAMA, YUKIHANE, SIBUKI, PETAL, TURN_PRINT, BODY_PRINT,
	KISHA_KEMURI, STEAM,
}

const GX := FieldCatalog.GX_TO_METERS
const SHADER := preload("res://shaders/field_effect.gdshader")
const EFFECT_DIR := "res://assets/generated/effects/%s.glb"
const FRAME_DIR := "res://assets/generated/textures/rel/%s.png"

## `eDT_*` (dust): prim colour per arg1, two-tile frames, lod and alpha per half-step.
const DUST_PRIM: Array[Color] = [
	Color8(255, 255, 255), Color8(255, 255, 255), Color8(255, 255, 255), Color8(255, 255, 255),
	Color8(255, 255, 255), Color8(230, 150, 100), Color8(100, 100, 255), Color8(230, 230, 100),
	Color8(255, 255, 255), Color8(255, 255, 255),
]
const DUST_TILES: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 2),
	Vector2i(2, 3), Vector2i(3, 3), Vector2i(3, 3), Vector2i(3, 3), Vector2i(0, 0),
]
const DUST_ALPHA: Array[int] = [0xFF, 0xC8, 0xC8, 0xC8, 0xC8, 0xC8, 0xC8, 0xC8, 0, 0]
const DUST_LOD: Array[int] = [0x00, 0x80, 0xFF, 0x80, 0x00, 0x80, 0xFF, 0x80, 0, 0]
## `eTDT_*` (tumble dust).
const TDUST_TILES: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 1), Vector2i(1, 1),
	Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(2, 2),
	Vector2i(2, 3), Vector2i(2, 3), Vector2i(3, 3), Vector2i(3, 3), Vector2i(3, 3),
]
const TDUST_LOD: Array[int] = [
	0xFF, 0xFF, 0x55, 0xAA, 0xFF, 0xFF, 0x55, 0xAA, 0xFF, 0xFF, 0x55, 0xAA, 0xFF, 0xFF, 0xFF
]
## `mzt_spd_data` / `ykd_spd_data`: {base_y, rng_y, base_z, relative_z}.
const MIZU_SPEED: Array[Vector4] = [
	Vector4(2.0, 1.5, 1.5, 2.0), Vector4(1.75, 2.0, 1.5, 1.75), Vector4(1.75, 2.0, 1.5, 2.25),
	Vector4(1.25, 1.35, 2.5, 0.0), Vector4(1.5, 3.0, 1.0, 0.0), Vector4(2.0, 3.0, 1.0, 0.0),
]
const MIZU_ANGLE: Array[int] = [
	0x0000, 0x071C, 0x2EEE, 0x1555, 0xE71D, 0xD99A, 0x5555, 0x4000, 0xC71D, 0xA667, 0xC000
]
const YUKI_SPEED: Array[Vector4] = [
	Vector4(1.5, 1.25, 1.0, 1.75), Vector4(2.0, 1.35, 1.0, 1.6), Vector4(2.0, 1.35, 1.0, 2.0),
	Vector4(1.5, 1.85, 1.5, 0.0), Vector4(2.0, 2.5, 1.0, 0.0),
]
const YUKI_ANGLE_DEG: Array[float] = [
	0.0, 9.997559, 65.994873, 29.998169, 325.00305, 306.002197, 119.998169, 90.0, 280.003052,
	234.003296,
]
## `Steam_tex_indx` / `Steam_plod_tbl` (`ef_steam`, 15 half-steps over 30 frames).
const STEAM_TILES: Array[Vector2i] = [
	Vector2i(0, 1), Vector2i(0, 1), Vector2i(0, 1), Vector2i(0, 1), Vector2i(2, 1),
	Vector2i(2, 1), Vector2i(2, 1), Vector2i(2, 1), Vector2i(2, 3), Vector2i(2, 3),
	Vector2i(2, 3), Vector2i(2, 3), Vector2i(3, 3), Vector2i(3, 3), Vector2i(3, 3),
]
const STEAM_LOD: Array[int] = [
	0x00, 0x40, 0x80, 0xC0, 0xFF, 0xC0, 0x80, 0x40, 0x00, 0x40, 0x80, 0xC0, 0xFF, 0xFF, 0xFF
]
## `eKishaK_dw`: `gDPSetPrimColor(0, 128, 30, 30, 30, alpha)`.
const KEMURI_PRIM := Color8(30, 30, 30)
const KEMURI_LOD := 128.0 / 255.0
## `ef_hanabira_model_tbl` by `arg0 / 3`; colour `arg0 % 3` → `flowerK_pal`.
const PETAL_MODELS: Array[String] = ["ef_hana01_pa_a", "ef_hana01_co_a", "ef_hana01_tu_a", "ef_hana01_ha_a"]
## `mFM_SetFGPal` `flower_pal_idx_table[term]`.
const FLOWER_PAL_IDX: Array[int] = [8, 8, 8, 0, 1, 1, 1, 2, 2, 3, 4, 5, 6, 7, 8, 8, 8, 8]

var kind: Kind = Kind.DUST
var arg0: int = 0
var arg1: int = 0
var timer: int = 0
var pos_gx: Vector3 = Vector3.ZERO
var vel: Vector3 = Vector3.ZERO
var acc: Vector3 = Vector3.ZERO
var scale_gx: Vector3 = Vector3.ONE * 0.01
var offset: Vector3 = Vector3.ZERO
var angle: float = 0.0
## Bounce counter / flags and spins (`effect_specific[]`).
var spec: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
## World-metre ground height sampler (`mCoBG_GetBgY_AngleS_FromWpos`).
var ground_y: Callable = Callable()
## Slope tilt for prints: basis that lays the quad on the ground.
var ground_basis: Basis = Basis.IDENTITY

var _holder: Node3D
var _mat: ShaderMaterial
var _steps := FrameStepper.new(DecompTime.TICK_HZ, 8.0)
var _frames: Array[Texture2D] = []


## Spawn under `host` (world `Effects` node). `pos` world metres, `yaw` radians.
static func spawn(
	host: Node, k: Kind, pos: Vector3, yaw: float, a0: int = 0, a1: int = 0,
	sampler: Callable = Callable(), slope: Basis = Basis.IDENTITY
) -> FieldFx:
	if host == null:
		return null
	var fx := FieldFx.new()
	fx.kind = k
	fx.arg0 = a0
	fx.arg1 = a1
	fx.angle = yaw
	fx.pos_gx = pos / GX
	fx.ground_y = sampler
	fx.ground_basis = slope
	if not fx._construct():
		fx.free()
		return null
	host.add_child(fx)
	fx._attach()
	fx._draw()
	return fx


static func rot_y(v: Vector3, a: float) -> Vector3:
	## `eEL_VectorRoteteY`.
	return Vector3(v.x * cos(a) + v.z * sin(a), v.y, -v.x * sin(a) + v.z * cos(a))


## `eEL_RandomFirstSpeed(speed, y, max_z, max_x)`.
static func random_first_speed(y: float, max_z: float, max_x: float) -> Vector3:
	var v := Vector3(0.0, y, 0.0)
	if max_z != 0.0:
		v = Basis(Vector3.BACK, deg_to_rad(randf() * max_z - max_z * 0.5)) * v
	if max_x != 0.0:
		v = Basis(Vector3.RIGHT, deg_to_rad(randf() * max_x - max_x * 0.5)) * v
	return v


## `eEL_CalcAdjust`.
static func calc_adjust(now: float, start: float, end: float, a: float, b: float) -> float:
	if start == end or now <= start:
		return a
	if now >= end:
		return b
	return a + (now - start) * ((b - a) / (end - start))


func _process(delta: float) -> void:
	_steps.add(delta)
	while _steps.next():
		_move()
		timer -= 1
		if timer <= 0:
			queue_free()
			return
	_draw()


func _ground(at_gx: Vector3) -> float:
	if not ground_y.is_valid():
		return -INF
	var y: float = ground_y.call(at_gx * GX)
	return y / GX if y > FieldCollision.NO_FLOOR + 1.0 else -INF


# --- construction (`*_init` + `*_ct`) --------------------------------------------------

func _construct() -> bool:
	match kind:
		Kind.DUST:
			_ct_dust()
		Kind.TUMBLE_DUST:
			_ct_tumble_dust()
		Kind.SAND:
			_ct_sand()
		Kind.MIZUTAMA:
			_ct_drop(MIZU_SPEED, -0.375)
			scale_gx = Vector3.ONE * 0.008
		Kind.YUKIDAMA:
			_ct_drop(YUKI_SPEED, -0.3)
			scale_gx = Vector3.ONE * (0.007 if int(spec[2]) == 0 else 0.006)
		Kind.YUKIHANE:
			timer = 16
			pos_gx.y += 0.5
			scale_gx = Vector3.ONE * 0.008
			vel = Vector3(0.0, 0.5, 0.0)
			acc = Vector3(0.0, -0.02, 0.0)
		Kind.SIBUKI:
			pos_gx.y -= 3.0
			pos_gx.z += 5.0
			scale_gx = Vector3.ONE * 0.011
			timer = 12
		Kind.PETAL:
			_ct_petal()
		Kind.KISHA_KEMURI:
			## `eKishaK_ct`: scale 0, 80 frames, ±2.5 GX jitter; `arg0 == 1` drifts by `arg1`.
			scale_gx = Vector3.ZERO
			timer = 80
			pos_gx.x += randf() * 5.0 - 2.5
			pos_gx.z += randf() * 5.0 - 2.5
			if arg0 == 1:
				var drift: float = float(arg1) * MLib.S16
				acc = Vector3(sin(drift) * 0.2, 0.0, cos(drift) * 0.2)
		Kind.STEAM:
			## `eSteam_ct`: puffs out along `angle` at 0.5…1.5, up 1.5…4.5 GX, rises back.
			var speed: float = randf() + 0.5
			scale_gx = Vector3.ONE * 0.005
			offset.x = 0.02
			vel = Vector3(sin(angle) * speed, -randf() * 3.0 - 1.5, cos(angle) * speed)
			acc = Vector3(0.0, 0.125, 0.0)
			timer = 30
		Kind.TURN_PRINT:
			return _ct_turn_print()
		Kind.BODY_PRINT:
			return _ct_body_print()
	return timer > 0


func _ct_dust() -> void:
	var v := Vector3(0.0, 1.0 if arg1 != 4 else 0.0, 0.25)
	if arg1 == 4:
		pos_gx.y += 5.0
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
			pos_gx += Vector3(15.0 * sin(angle), -15.0, 15.0 * cos(angle))
		9:
			v.z = 0.75
			pos_gx += Vector3(25.0 * sin(angle), 0.0, 25.0 * cos(angle))
	var a := Vector3(0.0, -0.05, 0.075)
	if arg1 == 4:
		a = Vector3(0.0, 0.1, 0.0)
	elif arg1 == 0:
		a = Vector3.ZERO
	var s := 0.01
	if arg1 == 4:
		s = 0.015
	elif arg1 == 0 or arg1 == 9:
		s = 0.007
	vel = rot_y(v, angle)
	acc = rot_y(a, angle)
	scale_gx = Vector3.ONE * s
	timer = 18


func _ct_tumble_dust() -> void:
	var z := 3.5
	match arg1:
		1:
			z = 3.75
		5, 7, 6, 8:
			z = 5.5
		9:
			z = 3.0
	vel = rot_y(Vector3(0.0, 0.5, z), angle)
	acc = rot_y(Vector3(0.0, 0.05, -0.05), angle)
	scale_gx = Vector3.ONE * 0.005
	offset.x = 0.02 if arg1 in [1, 5, 6] else 0.015
	if arg1 == 1 or arg1 == 3:
		timer = 32
	elif arg1 == 0 or arg1 == 4:
		timer = 34
	elif arg1 == 7 or arg1 == 8:
		timer = 36
	else:
		timer = 30


func _ct_sand() -> void:
	## `eSandsplash_init` + `_ct` (arg0 selects the throw).
	pos_gx.y -= 3.0
	pos_gx.z += 5.0
	vel = Vector3(0.0, 0.5, 0.0)
	acc = Vector3(0.0, -0.01, 0.0)
	offset = Vector3(0.005, 0.01, 0.0)
	if arg0 == 2:
		vel = Vector3(sin(angle), 0.5, cos(angle))
		acc = Vector3.ZERO
	elif arg0 == 1:
		vel = Vector3(sin(angle), 0.5, cos(angle))
		acc = Vector3(0.0, -0.075, 0.0)
		offset = Vector3(0.008, 0.012999999, 0.0)
	elif arg0 == 3:
		vel = Vector3(sin(angle) * 0.25, 0.0, cos(angle))
		acc = Vector3(0.0, -0.05, 0.0)
		offset = Vector3(0.006, 0.012, 0.0)
	timer = 16


func _ct_drop(table: Array[Vector4], gravity: float) -> void:
	## `eMizutama_ct` / `eYukidama_ct`: arg1 = speed set << 12 | direction index.
	timer = 50
	spec[2] = float((arg1 >> 12) & 0xF)
	spec[3] = float(arg1 & 0x0FFF)
	spec[0] = 0.0
	spec[1] = 1.0
	var sp: Vector4 = table[clampi(int(spec[2]), 0, table.size() - 1)]
	acc = Vector3(0.0, gravity, 0.0)
	var v := Vector3(0.0, sp.x + randf() * sp.y, sp.z)
	var dir: float
	if kind == Kind.MIZUTAMA:
		dir = angle + MLib.s16_to_rad(MIZU_ANGLE[clampi(int(spec[3]), 0, MIZU_ANGLE.size() - 1)])
	else:
		dir = angle + deg_to_rad(YUKI_ANGLE_DEG[clampi(int(spec[3]), 0, YUKI_ANGLE_DEG.size() - 1)])
	vel = rot_y(v, dir)
	vel.x += sin(angle) * sp.w
	vel.z += cos(angle) * sp.w
	pos_gx.x += (randf() - 0.5) * 6.0
	pos_gx.z += (randf() - 0.5) * 6.0
	offset.y = _ground(pos_gx) + 3.0


func _ct_petal() -> void:
	## `eHanabira_ct`: model `arg0 / 3`, colour `arg0 % 3`.
	spec[0] = float(arg0 / 3)
	spec[1] = float(arg0 % 3)
	timer = 60
	var v: float = randf() * 0.5 + 3.0
	if arg1 == 1 or arg1 == 2 or arg1 == 3:
		v *= 1.5
	vel = random_first_speed(v, 32.0, 32.0)
	acc = Vector3(0.0, -vel.y * 0.05, 0.0)
	offset = Vector3.ZERO
	spec[4] = randf() * TAU
	spec[2] = randf() * TAU
	spec[3] = randf() * TAU
	spec[5] = 0.0
	scale_gx = Vector3.ONE * 0.009


func _ct_turn_print() -> bool:
	## `eTurnFootPrint_ct`: (winter or sand/wave) and (grass or sand/wave).
	var winter: bool = Clock.season() == Clock.Season.WINTER
	var sandy: bool = arg0 == StepFx.ATTR_SAND or arg0 == StepFx.ATTR_WAVE
	if not ((winter or sandy) and (StepFx.is_grass(arg0) or sandy)):
		return false
	var g: float = _ground(pos_gx)
	if g > -INF:
		pos_gx.y = g + 2.0
	spec[3] = 1.0 if sandy else 0.0
	timer = 160
	return true


func _ct_body_print() -> bool:
	var winter_grass: bool = Clock.season() == Clock.Season.WINTER and StepFx.is_grass(arg0)
	var sandy: bool = arg0 == StepFx.ATTR_SAND or arg0 == StepFx.ATTR_WAVE
	if not (winter_grass or sandy):
		return false
	scale_gx = Vector3.ONE * 0.016
	pos_gx.x += sin(angle) * 7.0
	pos_gx.z += cos(angle) * 7.0
	var g: float = _ground(pos_gx)
	if g > -INF:
		pos_gx.y = g + 0.6
	spec[4] = 0.0
	if sandy:
		timer = 600
		spec[3] = 1.0
	else:
		timer = 800
		spec[3] = 0.0
	return true


# --- movement (`*_mv`) ------------------------------------------------------------------

func _move() -> void:
	match kind:
		Kind.DUST:
			if arg1 == 0 or arg1 == 9:
				vel *= sqrt(0.85)
			vel += acc
			pos_gx += vel
		Kind.TUMBLE_DUST:
			if timer <= 30:
				vel += acc
				pos_gx += vel
				acc.y *= sqrt(0.8)
				vel.y *= sqrt(0.95)
				vel.x *= sqrt(0.8)
				vel.z *= sqrt(0.8)
		Kind.SAND:
			vel += acc
			pos_gx += vel
		Kind.KISHA_KEMURI:
			pos_gx.y += calc_adjust(80 - timer, 0, 20, 2.2, 0.5)
			if arg0 == 1:
				pos_gx += Vector3(acc.x, 0.0, acc.z)
		Kind.STEAM:
			vel += acc
			pos_gx += vel
			vel *= sqrt(0.8)
			scale_gx = Vector3.ONE * calc_adjust(timer, 0, 16, offset.y, offset.x)
		Kind.MIZUTAMA, Kind.YUKIDAMA:
			_move_drop()
		Kind.YUKIHANE:
			vel += acc
			pos_gx += vel
		Kind.PETAL:
			_move_petal()
		Kind.BODY_PRINT:
			if scale_gx.x < 0.021:
				scale_gx.x += 0.0005
				scale_gx.z = scale_gx.x
			## A hole dug through the print wipes it early (`timer -= 70` per frame).
			if spec[4] != 1.0 and StepFx.hole_at(pos_gx * GX):
				spec[4] = 1.0
			if spec[4] == 1.0 and timer >= 70:
				timer -= 70


func _move_drop() -> void:
	## Bounce up to 6 times on the ground (`effect_specific[0]` counts landings).
	if spec[0] == 0.0:
		offset.z = offset.y
		offset.y = _ground(pos_gx) + 3.0
		offset.x = pos_gx.y
		vel += acc
		pos_gx += vel
	var landed: bool = (
		(pos_gx.y <= offset.y and offset.x > offset.y)
		or (offset.y > offset.x and offset.z <= offset.x)
	)
	if not landed:
		return
	if pos_gx.y - offset.y > vel.y:
		pos_gx.y = offset.y
	if spec[1] == 1.0:
		if spec[0] < 6.0:
			spec[0] += 1.0
			spec[1] = 0.0
		else:
			timer = 0
	else:
		spec[1] = 1.0


func _move_petal() -> void:
	vel += acc
	pos_gx += vel
	if spec[5] == 0.0:
		spec[4] += MLib.s16_to_rad(0xA00)
		spec[2] += MLib.s16_to_rad(0x280)
		spec[3] += MLib.s16_to_rad(0x280)
		if vel.y <= 0.0:
			spec[5] = 1.0
			acc.y = -0.05
	else:
		var s: float = sin(spec[4]) * 2.0
		offset = Vector3(s, 0.0, -s)
		spec[4] += MLib.s16_to_rad(0xA00)
		spec[2] += MLib.s16_to_rad(0x662)
		spec[3] += MLib.s16_to_rad(0x662)


# --- presentation (`*_dw`) ------------------------------------------------------------

func _model_id() -> String:
	match kind:
		Kind.DUST, Kind.TUMBLE_DUST:
			return "ef_dust01"
		Kind.SAND:
			return "ef_sunahane01_00"
		Kind.MIZUTAMA:
			return "ef_koke_suiteki01_00"
		Kind.YUKIDAMA:
			return "ef_koke_yuki01_00"
		Kind.YUKIHANE:
			return "ef_yukihane01_00"
		Kind.SIBUKI:
			return "ef_sibuki01_00"
		Kind.PETAL:
			return PETAL_MODELS[clampi(int(spec[0]), 0, 3)]
		Kind.TURN_PRINT:
			return "ef_turn_footprint"
		Kind.KISHA_KEMURI:
			return "ef_kisha_kemuri01"
		Kind.STEAM:
			return "ef_dust01"
		_:
			return "ef_bodyprint01_00"


func _frame_names() -> Array[String]:
	match kind:
		Kind.DUST, Kind.TUMBLE_DUST, Kind.STEAM:
			return ["ef_dust01_0", "ef_dust01_1", "ef_dust01_2", "ef_dust01_3"]
		Kind.KISHA_KEMURI:
			return ["ef_kisha_kemuri01_0", "ef_kisha_kemuri01_1"]
		Kind.SAND:
			return _numbered("ef_sunahane01_%d_inta_ia8", 0, 3)
		Kind.MIZUTAMA:
			return _numbered("ef_koke_suiteki01_%d_int_i4", 0, 3)
		Kind.YUKIDAMA:
			return _numbered("ef_koke_yuki01_%d_inta_ia8", 0, 3)
		Kind.YUKIHANE:
			return _numbered("ef_yukihane01_%d_inta_ia8", 0, 3)
		Kind.SIBUKI:
			return _numbered("ef_sibuki01_%d_int_i4", 1, 4)
		Kind.PETAL:
			## `mFM_obj_a_01_flower_pal[K * 9 + flower_pal_idx]` rows (pipeline `_pNN`).
			var row: int = int(spec[1]) * 9 + FLOWER_PAL_IDX[clampi(Clock.term_idx(), 0, 17)]
			return ["%s_tex_p%02d" % [_model_id(), row]]
	return []


static func _numbered(pattern: String, from: int, to: int) -> Array[String]:
	var out: Array[String] = []
	for i: int in range(from, to + 1):
		out.append(pattern % i)
	return out


func _attach() -> void:
	var path := EFFECT_DIR % _model_id()
	if not ResourceLoader.exists(path):
		return
	var inst: Node = (load(path) as PackedScene).instantiate()
	_holder = Node3D.new()
	_holder.add_child(inst)
	add_child(_holder)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	var glb_tex: Texture2D = null
	for node: Node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i: int in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if src != null and src.albedo_texture != null and glb_tex == null:
				glb_tex = src.albedo_texture
			mi.set_surface_override_material(i, _mat)
	for frame: String in _frame_names():
		var fpath := FRAME_DIR % frame
		_frames.append(load(fpath) as Texture2D if ResourceLoader.exists(fpath) else glb_tex)
	if _frames.is_empty():
		_frames.append(glb_tex)
	_mat.set_shader_parameter(&"tex0", _frames[0])
	_mat.set_shader_parameter(&"tex1", _frames[0])


func _draw() -> void:
	if _holder == null:
		return
	global_position = pos_gx * GX
	var s: Vector3 = scale_gx * GX / FieldCatalog.PIPELINE_SCALE
	var basis := Basis.IDENTITY
	var billboard := false
	var mode := 0
	var prim := Color(1, 1, 1, 1)
	var env := Color(0, 0, 0, 1)
	var lod := 0.0
	var f0 := 0
	var f1 := 0
	match kind:
		Kind.DUST:
			var c: int = clampi((18 - timer) >> 1, 0, 9)
			f0 = DUST_TILES[c].x
			f1 = DUST_TILES[c].y
			var tint: Color = DUST_PRIM[arg1] if arg1 >= 0 and arg1 < 10 else Color.WHITE
			prim = Color(tint, DUST_ALPHA[c] / 255.0)
			lod = DUST_LOD[c] / 255.0
			mode = 1
			billboard = true
		Kind.TUMBLE_DUST:
			var counter: int = 30 - timer
			var idx: int = clampi(counter >> 1, 0, 14)
			f0 = TDUST_TILES[idx].x
			f1 = TDUST_TILES[idx].y
			s = Vector3.ONE * calc_adjust(counter, 0, 30, 0.005, offset.x) * GX / FieldCatalog.PIPELINE_SCALE
			prim = Color(1, 1, 1, calc_adjust(counter, 8, 30, 255.0, 120.0) / 255.0)
			lod = TDUST_LOD[idx] / 255.0
			mode = 1
			billboard = true
		Kind.KISHA_KEMURI:
			var kt: int = 80 - timer
			s = Vector3.ONE * calc_adjust(kt, 0, 40, 0.003, 0.027) * GX / FieldCatalog.PIPELINE_SCALE
			prim = Color(KEMURI_PRIM, int(calc_adjust(kt, 40, 80, 200.0, 4.0)) / 255.0)
			f0 = 0
			f1 = 1
			lod = KEMURI_LOD
			mode = 1
			billboard = true
		Kind.STEAM:
			var sc: int = 30 - timer
			var si: int = clampi(sc >> 1, 0, 14)
			f0 = STEAM_TILES[si].x
			f1 = STEAM_TILES[si].y
			s = Vector3.ONE * calc_adjust(sc, 0, 30, 0.005, offset.x) * GX / FieldCatalog.PIPELINE_SCALE
			prim = Color(1, 1, 1, 1)
			lod = STEAM_LOD[si] / 255.0
			mode = 1
			billboard = true
		Kind.SAND:
			f0 = clampi((16 - timer) >> 1, 0, 7) >> 1
			basis = Basis(Vector3.RIGHT, deg_to_rad(-45.0))
			prim = Color8(20, 20, 20, 255)
			env = Color8(205, 180, 140, 255)
			mode = 3
		Kind.MIZUTAMA:
			f0 = clampi(int(spec[0]) >> 1, 0, 3)
			s = Vector3.ONE * calc_adjust(timer, 0, 40, 0.004, 0.008) * GX / FieldCatalog.PIPELINE_SCALE
			prim = Color8(200, 255, 255, 200)
			billboard = true
		Kind.YUKIDAMA:
			f0 = clampi(int(spec[0]) >> 1, 0, 3)
			s = Vector3.ONE * calc_adjust(timer, 10, 30, 0.0035, 0.007) * GX / FieldCatalog.PIPELINE_SCALE
			prim = Color8(100, 160, 240, 255)
			mode = 2
			billboard = true
		Kind.YUKIHANE:
			f0 = clampi((16 - timer) >> 1, 0, 7) >> 1
			basis = Basis(Vector3.RIGHT, deg_to_rad(-45.0))
			prim = Color8(50, 80, 120, 230)
			mode = 2
		Kind.SIBUKI:
			var sidx: int = clampi((12 - timer) >> 1, 0, 5)
			if sidx < 2:
				_holder.visible = false
				return
			_holder.visible = true
			f0 = sidx - 2
			basis = Basis(Vector3.RIGHT, deg_to_rad(-30.0))
			prim = Color8(200, 255, 255, 155 if arg0 == 0 else 235)
		Kind.PETAL:
			global_position = (pos_gx + offset) * GX
			basis = Basis.from_euler(Vector3(spec[2], 0.0, spec[3]), EULER_ORDER_ZXY)
			prim = Color(1, 1, 1, calc_adjust(timer, 0, 20, 0.0, 255.0) / 255.0)
			mode = 4
		Kind.TURN_PRINT:
			var counter2: int = 160 - timer
			var sc: float = calc_adjust(counter2, 2, 8, 0.0054375003, 0.0072500003)
			s = Vector3(sc, 0.0072500003, sc) * GX / FieldCatalog.PIPELINE_SCALE
			basis = ground_basis * Basis(Vector3.UP, angle)
			var a: float = calc_adjust(counter2, 118, 159, 150.0, 0.0) / 255.0
			prim = Color8(70, 50, 50) if spec[3] == 1.0 else Color8(0, 50, 100)
			prim.a = a
		Kind.BODY_PRINT:
			var counter3: int = 800 - timer
			var ba: float
			if spec[3] == 1.0:
				ba = calc_adjust(counter3, 360, 600, 150.0, 0.0)
			else:
				ba = calc_adjust(counter3, 500, 799, 150.0, 0.0)
			basis = ground_basis * Basis(Vector3.UP, angle)
			prim = Color8(70, 50, 50) if spec[3] == 1.0 else Color8(0, 50, 100)
			prim.a = ba / 255.0
	_holder.basis = basis * Basis.from_scale(s)
	_mat.set_shader_parameter(&"intensity_alpha", kind in [
		Kind.DUST, Kind.TUMBLE_DUST, Kind.MIZUTAMA, Kind.SIBUKI, Kind.TURN_PRINT, Kind.BODY_PRINT,
		Kind.KISHA_KEMURI, Kind.STEAM,
	])
	_mat.set_shader_parameter(&"mode", mode)
	_mat.set_shader_parameter(&"billboard", billboard)
	_mat.set_shader_parameter(&"prim_color", prim)
	_mat.set_shader_parameter(&"env_color", env)
	_mat.set_shader_parameter(&"lod_frac", lod)
	if not _frames.is_empty():
		_mat.set_shader_parameter(&"tex0", _frames[clampi(f0, 0, _frames.size() - 1)])
		_mat.set_shader_parameter(&"tex1", _frames[clampi(f1, 0, _frames.size() - 1)])
