class_name FieldFx
extends Node3D

## The effect controller's field effects (`StepFx` decides which to spawn). `spawn` is the one
## entry point:
## - particles (dust, steam, smoke, sand / water / snow kicks, drops, umbrella spray) go to
##   `FieldParticle`, one-shot GPU particles;
## - the rest are this node, run on seconds by a `Tween` on `age`: a flower petal
##   (`ef_hanabira`), turn footprints and tumble body prints (`ef_turn_footprint`,
##   `ef_tumble_bodyprint`), the water ring (`ef_turi_hamon`), and the umbrella twirl's
##   spray source (`ef_kasamizu`), which flicks a drop every other tick while it rains.
## The decomp's GX-per-tick numbers are converted where they are used. The tables here are
## shared with `FieldParticle`.

enum Kind {
	DUST, TUMBLE_DUST, SAND, MIZUTAMA, YUKIDAMA, YUKIHANE, SIBUKI, PETAL, TURN_PRINT, BODY_PRINT,
	KISHA_KEMURI, STEAM, HAMON, KASAMIZU, KASAMIZUTAMA, SOBA_YUGE,
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
## `eSoba_Yuge_2tile_texture_idx` / `eSoba_Yuge_prim_f`, one row per two ticks of 44.
const YUGE_TILES: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(0, 0), Vector2i(0, 0), Vector2i(0, 0), Vector2i(0, 0), Vector2i(0, 0),
	Vector2i(0, 1), Vector2i(0, 1), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 2),
	Vector2i(1, 2), Vector2i(2, 2), Vector2i(2, 3), Vector2i(2, 3), Vector2i(2, 3), Vector2i(3, 3),
	Vector2i(3, 3), Vector2i(3, 3), Vector2i(3, 3), Vector2i(3, 3),
]
const YUGE_LOD: Array[int] = [0, 0, 0, 0, 0, 0, 64, 128, 192, 0, 64, 128, 192, 0, 64, 128, 192, 0, 0, 0, 0, 0]
## `eKishaK_dw`: `gDPSetPrimColor(0, 128, 30, 30, 30, alpha)`.
const KEMURI_PRIM := Color8(30, 30, 30)
const KEMURI_LOD := 128.0 / 255.0
## `eTH_ct`: ring size per `arg0` (5 and up grow with `arg1`).
const HAMON_SIZE: Array[float] = [0.036, 0.032, 0.024, 0.02, 0.014]
const HAMON_ENV := Color8(0, 50, 50)
## `eKasamizu_ct`: the spray leaves 45 GX up and 20 behind; a drop every other tick in rain.
const KASAMIZU_FROM := Vector3(0.0, 45.0, -20.0)
## `eKasamizutama_scale_table` (× 0.005), one row per two ticks.
const KASAMIZUTAMA_SCALE: Array[float] = [0.0, 0.1, 0.3, 0.5, 0.7, 0.9, 1.0, 0.9, 0.7, 0.5]
## `ef_hanabira_model_tbl` by `arg0 / 3`; colour `arg0 % 3` → `flowerK_pal`.
const PETAL_MODELS: Array[String] = ["ef_hana01_pa_a", "ef_hana01_co_a", "ef_hana01_tu_a", "ef_hana01_ha_a"]
## `mFM_SetFGPal` `flower_pal_idx_table[term]`.
const FLOWER_PAL_IDX: Array[int] = [8, 8, 8, 0, 1, 1, 1, 2, 2, 3, 4, 5, 6, 7, 8, 8, 8, 8]

var kind: Kind = Kind.PETAL
var arg0: int = 0
var arg1: int = 0
var angle: float = 0.0
## Seconds since it appeared; the tween runs it to `lifetime`, and setting it redraws.
var age: float = 0.0:
	set(value):
		age = value
		_redraw()
var lifetime: float = 1.0
## Where it started (metres) and, for a petal, its launch velocity (m/s).
var origin: Vector3 = Vector3.ZERO
var launch: Vector3 = Vector3.ZERO
## World-metre ground height sampler (`mCoBG_GetBgY_AngleS_FromWpos`).
var ground_y: Callable = Callable()
## Slope tilt for prints: basis that lays the quad on the ground.
var ground_basis: Basis = Basis.IDENTITY
## Prints on sand rather than snow; a body print a hole has been dug through.
var sandy: bool = false
var wiped: bool = false
## Water ring: size it eases out to, from where, how fast, its starting alpha, its drift.
var ring_size: float = 0.02
var ring_start: float = 0.001
var ring_half_life: float = 0.1
var ring_alpha: float = 150.0
var ring_drift: float = 0.125 * GX * 60.0
## Petal: spins and sway phase at launch.
var _spin0: Vector2 = Vector2.ZERO
var _sway0: float = 0.0
## Umbrella spray: drops still to flick.
var drops_left: int = 0

var _holder: Node3D
var _mat: ShaderMaterial
var _frames: Array[Texture2D] = []
var _tween: Tween = null


## Spawn under `host` (world `Effects` node). `pos` world metres, `yaw` radians. Particle kinds
## go to `FieldParticle` and return null.
static func spawn(
	host: Node, k: Kind, pos: Vector3, yaw: float, a0: int = 0, a1: int = 0,
	sampler: Callable = Callable(), slope: Basis = Basis.IDENTITY
) -> FieldFx:
	if host == null:
		return null
	if FieldParticle.handles(k):
		FieldParticle.spawn(host, k, pos, yaw, a0, a1, sampler)
		return null
	var fx := FieldFx.new()
	fx.kind = k
	fx.arg0 = a0
	fx.arg1 = a1
	fx.angle = yaw
	fx.origin = pos
	fx.ground_y = sampler
	fx.ground_basis = slope
	if not fx._construct():
		fx.free()
		return null
	host.add_child(fx)
	fx._attach()
	fx._start()
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


## `eEL_CalcAdjust`: `a` up to `start`, `b` from `end`, linear between.
static func calc_adjust(now: float, start: float, end: float, a: float, b: float) -> float:
	if start == end or now <= start:
		return a
	if now >= end:
		return b
	return a + (now - start) * ((b - a) / (end - start))


static func _ticks(n: float) -> float:
	return n / 60.0


func _ground(at: Vector3) -> float:
	if not ground_y.is_valid():
		return -INF
	var y: float = ground_y.call(at)
	return y if y > FieldCollision.NO_FLOOR + 1.0 else -INF


# --- construction (`*_ct`) --------------------------------------------------------------

func _construct() -> bool:
	match kind:
		Kind.PETAL:
			_ct_petal()
		Kind.HAMON:
			_ct_hamon()
		Kind.KASAMIZU:
			origin += rot_y(KASAMIZU_FROM, angle) * GX
			lifetime = _ticks(24)
			drops_left = 12
		Kind.TURN_PRINT:
			return _ct_turn_print()
		Kind.BODY_PRINT:
			return _ct_body_print()
		_:
			return false
	return true


## `eHanabira_ct`: model `arg0 / 3`, colour `arg0 % 3`; thrown up at 3–3.5 GX a tick (×1.5
## for a run), braked at a twentieth of its climb, then falling and swaying; 60 ticks.
func _ct_petal() -> void:
	lifetime = _ticks(60)
	var v: float = randf() * 0.5 + 3.0
	if arg1 == 1 or arg1 == 2 or arg1 == 3:
		v *= 1.5
	launch = random_first_speed(v, 32.0, 32.0) * GX * 60.0
	_spin0 = Vector2(randf() * TAU, randf() * TAU)
	_sway0 = randf() * TAU


## `eTH_ct`: `arg0` 0–4 pick the ring's size (5+ scale with `arg1`); 4 is the slow wide one
## (52 ticks), 6 a slow drift; the rest live 32 ticks. Big rings start at alpha 200, small
## ones at 150. `angle` is the flow it drifts along.
func _ct_hamon() -> void:
	if arg0 >= 0 and arg0 < HAMON_SIZE.size():
		ring_size = HAMON_SIZE[arg0]
	else:
		ring_size = float(arg1) / 100.0 * 0.06 + 0.02
	ring_alpha = 200.0 if ring_size > 0.03 else 150.0
	var ticks: float = 32.0
	match arg0:
		6:
			ticks = 52.0
			ring_start = 0.001
			ring_drift = 0.05 * GX * 60.0
		4:
			ticks = 52.0
			ring_start = 0.003
			ring_drift = 0.35 * GX * 60.0
		_:
			ring_start = 0.001
			ring_drift = 0.125 * GX * 60.0
	lifetime = _ticks(ticks)
	## `add_calc2(scale, size, 1 − √(1 − 1/life), 0.005)` a tick: never near the step cap, so
	## the gap halves on a fixed clock.
	ring_half_life = Motion.half_life_from_fraction(1.0 - sqrt(1.0 - 1.0 / ticks))


func _ct_turn_print() -> bool:
	## `eTurnFootPrint_ct`: (winter or sand/wave) and (grass or sand/wave).
	var winter: bool = Clock.season() == Clock.Season.WINTER
	sandy = arg0 == StepFx.ATTR_SAND or arg0 == StepFx.ATTR_WAVE
	if not ((winter or sandy) and (StepFx.is_grass(arg0) or sandy)):
		return false
	var g: float = _ground(origin)
	if g > -INF:
		origin.y = g + 2.0 * GX
	lifetime = _ticks(160)
	return true


func _ct_body_print() -> bool:
	var winter_grass: bool = Clock.season() == Clock.Season.WINTER and StepFx.is_grass(arg0)
	sandy = arg0 == StepFx.ATTR_SAND or arg0 == StepFx.ATTR_WAVE
	if not (winter_grass or sandy):
		return false
	origin += Vector3(sin(angle), 0.0, cos(angle)) * 7.0 * GX
	var g: float = _ground(origin)
	if g > -INF:
		origin.y = g + 0.6 * GX
	lifetime = _ticks(600 if sandy else 800)
	return true


# --- running ----------------------------------------------------------------------------

func _start() -> void:
	_redraw()
	if kind == Kind.KASAMIZU:
		## `eKasamizu_mv`: a drop every other tick while it rains (`game_frame & 1`).
		var timer := Timer.new()
		timer.wait_time = _ticks(2)
		timer.timeout.connect(emit_drop)
		add_child(timer)
		timer.start()
	_tween = create_tween()
	_tween.tween_property(self, "age", lifetime, lifetime).from(0.0)
	_tween.tween_callback(queue_free)


func _process(_delta: float) -> void:
	## A hole dug through a body print wipes it fast (`timer -= 70` a frame).
	if kind == Kind.BODY_PRINT and not wiped and StepFx.hole_at(origin):
		wiped = true
		if _tween != null:
			_tween.kill()
		_tween = create_tween()
		_tween.tween_property(self, "age", lifetime, (lifetime - age) / 70.0)
		_tween.tween_callback(queue_free)


## One spray drop (`ef_kasamizutama`), if it is raining.
func emit_drop() -> void:
	if drops_left <= 0:
		return
	drops_left -= 1
	if Weather.is_raining() and get_parent() != null:
		FieldParticle.spawn(get_parent(), Kind.KASAMIZUTAMA, origin, angle)


## Petal position relative to its start, `t` seconds in: rising while braked at a twentieth
## of its climb, then falling at 0.05 GX/tick² (`eHanabira_mv`).
func petal_offset(t: float) -> Vector3:
	var rise_g: float = launch.y * 0.05 * 60.0
	var fall_g: float = 0.05 * GX * 3600.0
	var turn: float = launch.y / rise_g if launch.y > 0.0 else 0.0
	var flat := Vector3(launch.x, 0.0, launch.z) * t
	if t <= turn:
		return flat + Vector3(0.0, launch.y * t - 0.5 * rise_g * t * t, 0.0)
	var top: float = launch.y * turn - 0.5 * rise_g * turn * turn
	var u: float = t - turn
	return flat + Vector3(0.0, top - 0.5 * fall_g * u * u, 0.0)


## Water ring scale, opacity (0–1) and drift at `t` seconds.
func ring_scale(t: float) -> float:
	return Motion.damp(ring_start, ring_size, ring_half_life, t)


func ring_opacity(t: float) -> float:
	return ring_alpha / 255.0 * clampf(1.0 - t / lifetime, 0.0, 1.0)


func ring_offset(t: float) -> Vector3:
	return Vector3(sin(angle), 0.0, cos(angle)) * ring_drift * t


# --- presentation (`*_dw`) ------------------------------------------------------------

func _model_id() -> String:
	match kind:
		Kind.PETAL:
			return PETAL_MODELS[clampi(arg0 / 3, 0, 3)]
		Kind.TURN_PRINT:
			return "ef_turn_footprint"
		Kind.HAMON:
			return "ef_turi_hamon01_00"
		Kind.BODY_PRINT:
			return "ef_bodyprint01_00"
	return ""


func _frame_names() -> Array[String]:
	match kind:
		Kind.HAMON:
			return ["ef_turi_hamon01_0"]
		Kind.PETAL:
			## `mFM_obj_a_01_flower_pal[K * 9 + flower_pal_idx]` rows (pipeline `_pNN`).
			var row: int = (arg0 % 3) * 9 + FLOWER_PAL_IDX[clampi(Clock.term_idx(), 0, 17)]
			return ["%s_tex_p%02d" % [_model_id(), row]]
	return []


func _attach() -> void:
	var path := EFFECT_DIR % _model_id()
	if _model_id() == "" or not ResourceLoader.exists(path):
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
	_mat.set_shader_parameter(&"intensity_alpha", kind != Kind.PETAL)
	_mat.set_shader_parameter(&"mirror_uv", kind == Kind.HAMON)


func _redraw() -> void:
	if not is_inside_tree():
		return
	global_position = origin
	if _holder == null:
		return
	var ticks: float = age * 60.0
	var s := Vector3.ONE * 0.01
	var basis := Basis.IDENTITY
	var mode := 0
	var prim := Color(1, 1, 1, 1)
	var env := Color(0, 0, 0, 1)
	match kind:
		Kind.HAMON:
			global_position = origin + ring_offset(age)
			s = Vector3.ONE * ring_scale(age)
			prim = Color(1, 1, 1, ring_opacity(age))
			env = HAMON_ENV
			mode = 5
		Kind.PETAL:
			var rising: bool = age <= (launch.y / (launch.y * 0.05 * 60.0) if launch.y > 0.0 else 0.0)
			var spin: float = (0x280 if rising else 0x662) * MLib.S16 * 60.0
			var sway: float = _sway0 + 0xA00 * MLib.S16 * 60.0 * age
			var side: float = 0.0 if rising else sin(sway) * 2.0 * GX
			global_position = origin + petal_offset(age) + Vector3(side, 0.0, -side)
			s = Vector3.ONE * 0.009
			basis = Basis.from_euler(Vector3(_spin0.x + spin * age, 0.0, _spin0.y + spin * age), EULER_ORDER_ZXY)
			prim = Color(1, 1, 1, calc_adjust((lifetime - age) * 60.0, 0, 20, 0.0, 255.0) / 255.0)
			mode = 4
		Kind.TURN_PRINT:
			var sc: float = calc_adjust(ticks, 2, 8, 0.0054375003, 0.0072500003)
			s = Vector3(sc, 0.0072500003, sc)
			basis = ground_basis * Basis(Vector3.UP, angle)
			prim = Color8(70, 50, 50) if sandy else Color8(0, 50, 100)
			prim.a = calc_adjust(ticks, 118, 159, 150.0, 0.0) / 255.0
		Kind.BODY_PRINT:
			## Widens 0.0005 a tick from 0.016 to 0.021.
			var w: float = minf(0.016 + 0.0005 * ticks, 0.021)
			s = Vector3(w, 0.016, w)
			basis = ground_basis * Basis(Vector3.UP, angle)
			prim = Color8(70, 50, 50) if sandy else Color8(0, 50, 100)
			prim.a = (calc_adjust(ticks, 360, 600, 150.0, 0.0) if sandy else calc_adjust(ticks, 500, 799, 150.0, 0.0)) / 255.0
	_holder.basis = basis * Basis.from_scale(s * GX / FieldCatalog.PIPELINE_SCALE)
	_mat.set_shader_parameter(&"mode", mode)
	_mat.set_shader_parameter(&"billboard", false)
	_mat.set_shader_parameter(&"prim_color", prim)
	_mat.set_shader_parameter(&"env_color", env)
	_mat.set_shader_parameter(&"lod_frac", 0.0)
