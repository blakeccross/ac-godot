class_name PondMoon
extends Node3D

## The full moon reflected on the pond at the Harvest Moon festival (`ef_night13_moon`,
## spawned by `harvestmoon_start`). It sits over the pool block's centre, 19 GX above the
## block, and glides from 100 GX east of the centre to 100 GX west between 18:00 and 21:00
## (`eNight13Moon_GetNowMoonPos`), bobbing on a 1.5 GX sway and rippling along two rotating
## axes. Drawn at scale 0.049 in xz with PRIM (255, 255, 100, 170) (see `pond_moon.gdshader`).

const VISUAL := &"ef_moon01_01"
const LIFT_GX := 19.0
const TRAVEL_GX := 100.0
const START_HOUR := 18
const END_HOUR := 21
const SWAY_GX := 1.5
const RIPPLE := 1.075
const SCALE := 0.049
const SHADER := preload("res://shaders/pond_moon.gdshader")
const DISC_TEX := "res://assets/generated/effects/ef_moon01_disc.png"
const RIPPLE_TEX := "res://assets/generated/effects/ef_moon01_ripple.png"
## s16 angle steps per 60 Hz frame (`effect_specific[0..2]`).
const STEP_0 := 150
const STEP_1 := -100
const STEP_2 := 256

## The pool block's centre at its base height (`eNight13Moon_GetPoolBlockCenter`).
var pond_center: Vector3 = Vector3.INF
## For `capture_world` `target=visual:`.
var visual_id: StringName = VISUAL

var _model: Node3D = null
var _a0: int = 0
var _a1: int = 0
var _a2: int = 0
var _accum: float = 0.0


func _ready() -> void:
	_model = GeneratedVisual.instantiate_raw(VISUAL)
	if _model == null:
		return
	_model.name = "Moon"
	_model.top_level = true
	add_child(_model)
	_tint(_model)
	_place()


## The GLB keeps one tile; the two-texture combiner lives in `pond_moon.gdshader`.
static func _tint(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		## After the pond water (`VisualWaterMaterials`, priority 2), which composites
		## opaquely over whatever the transparent pass drew before it.
		mat.render_priority = 3
		for pair: Array in [["disc_tex", DISC_TEX], ["ripple_tex", RIPPLE_TEX]]:
			if ResourceLoader.exists(str(pair[1])):
				mat.set_shader_parameter(str(pair[0]), load(str(pair[1])))
		for i: int in (mi.mesh.get_surface_count() if mi.mesh != null else 0):
			mi.set_surface_override_material(i, mat)
	for child: Node in node.get_children():
		_tint(child)


## `mFI_BkNum2BaseHeight`: the block's low ground (its lowest corner), at the block centre.
static func pond_base(mgr: EventManager, block: Vector2i) -> Vector3:
	var center: Vector3 = mgr.cell_position(EventManager.block_unit_to_cell(block, Vector2i(8, 8)))
	var base: float = INF
	for u: Vector2i in [Vector2i(0, 0), Vector2i(15, 0), Vector2i(0, 15), Vector2i(15, 15)]:
		base = minf(base, mgr.cell_position(EventManager.block_unit_to_cell(block, u)).y)
	center.y = base
	return center


## `eNight13Moon_GetNowMoonPos`: x offset from the pond centre in GX for the clock.
static func glide_x_gx(hour: int, minute: int, second: int) -> float:
	if hour < START_HOUR:
		return TRAVEL_GX
	if hour >= END_HOUR:
		return -TRAVEL_GX
	var span: float = TRAVEL_GX * 2.0 / float(END_HOUR - START_HOUR)
	return TRAVEL_GX - float(hour - START_HOUR) * span - (minute * 60.0 + second) / 54.0


func _physics_process(delta: float) -> void:
	if _model == null:
		return
	_accum += delta * 60.0
	while _accum >= 1.0:
		_accum -= 1.0
		_a0 = _wrap(_a0 + STEP_0)
		_a1 = _wrap(_a1 + STEP_1)
		_a2 = _wrap(_a2 + STEP_2)
	_place()


static func _wrap(a: int) -> int:
	return ((a + 0x8000) & 0xFFFF) - 0x8000


static func _rad(a: int) -> float:
	return float(a) * TAU / 65536.0


func _place() -> void:
	var center: Vector3 = pond_center if pond_center != Vector3.INF else global_position
	var gx := FieldCatalog.GX_TO_METERS
	var sway: float = SWAY_GX * sin(_rad(_a2))
	var pos := center + Vector3(
		(glide_x_gx(Clock.hour, Clock.minute, Clock.second) + sway) * gx, LIFT_GX * gx, -sway * gx)
	## RotY(-a0)·Scale(1.075,1,1)·RotY(a0) · RotY(-a1)·Scale(1,1,1.075)·RotY(a1) · Scale(0.049,1,0.049).
	var r0 := Basis(Vector3.UP, _rad(_a0))
	var r1 := Basis(Vector3.UP, _rad(_a1))
	var basis := r0.inverse() * Basis.from_scale(Vector3(RIPPLE, 1.0, 1.0)) * r0
	basis = basis * r1.inverse() * Basis.from_scale(Vector3(1.0, 1.0, RIPPLE)) * r1
	basis = basis * Basis.from_scale(Vector3(SCALE, 1.0, SCALE) * gx / FieldCatalog.PIPELINE_SCALE)
	_model.global_transform = Transform3D(basis, pos)
