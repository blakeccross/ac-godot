class_name TreeFx
extends Node3D

## Falling leaves and winter snow puffs from a shaken tree — `eEC_EFFECT_BUSH_HAPPA`
## (`ef_bush_happa.c`) and `eEC_EFFECT_BUSH_YUKI` (`ef_bush_yuki.c`), stepped on the
## effect controller's 60 Hz tick. Positions / speeds are GX (40 GX = 2 m); the node
## works in metres.

enum Kind { LEAF, SNOW }

const TICK := 1.0 / 60.0
const GX := FieldCatalog.GX_TO_METERS

## `EffectBG_Make_Leafs`: crown of a shaken tree, ±40 GX jitter (±30 for a medium cedar).
const CROWN_GX := 90.0
const SPREAD_GX := 40.0
const SPREAD_CEDAR_MED_GX := 30.0

## `eBushHappa_ct` arg1 4 (6 in cherry season) = shake leaf; scale 0.0106 on authored verts.
const LEAF_SCALE := 0.0106
const LEAF_LIFE := 80
const LEAF_FADE_TICKS := 28.0
## `eBushYuki_ct`: 60 ticks, scale 0.005, fades after 32.
const SNOW_SCALE := 0.005
const SNOW_LIFE := 60
const SNOW_FADE_FROM := 32.0
const SNOW_ALPHA := 200.0 / 255.0
const CHERRY_TERM := 4
const GOLD_TINT := Color(1.0, 0.86, 0.35)

var _kind: Kind = Kind.LEAF
var _velocity: Vector3 = Vector3.ZERO  ## GX / tick
var _accel: Vector3 = Vector3.ZERO
var _pos_gx: Vector3 = Vector3.ZERO
var _timer: int = 0
var _life: int = 0
var _acc: float = 0.0
var _falling: bool = false
var _spin_x: float = 0.0  ## radians
var _spin_z: float = 0.0
var _sway: float = 0.0
var _model: Node3D
var _base_scale: float = 1.0


## Drop one shake leaf near `crown` (world metres) of a tree in `family`.
static func leaf(host: Node, crown: Vector3, family: PlantData.Family, medium_cedar: bool) -> void:
	var fx := TreeFx.new()
	fx._kind = Kind.LEAF
	fx._setup_leaf(crown, family, medium_cedar)
	host.add_child(fx)
	fx.global_position = crown
	fx._attach_leaf_model(family)
	fx._sync()


## Winter only: one snow puff (`Make_Leafs` adds a `BUSH_YUKI` per call in winter).
static func snow(host: Node, crown: Vector3, medium_cedar: bool) -> void:
	var fx := TreeFx.new()
	fx._kind = Kind.SNOW
	fx._setup_snow(crown, medium_cedar)
	host.add_child(fx)
	fx.global_position = crown
	fx._attach_snow_model()
	fx._sync()


## `EffectBG_Make_Leafs` position: crown plus a random box around it.
static func jitter(crown: Vector3, medium_cedar: bool) -> Vector3:
	var spread: float = SPREAD_CEDAR_MED_GX if medium_cedar else SPREAD_GX
	return crown + Vector3(_rand2(), _rand2(), _rand2()) * spread * GX


static func _rand() -> float:
	return randf()


## `fqrand2`: [-0.5, 0.5).
static func _rand2() -> float:
	return randf() - 0.5


func _setup_leaf(crown: Vector3, family: PlantData.Family, medium_cedar: bool) -> void:
	var start: Vector3 = jitter(crown, medium_cedar) / GX
	## `eBushHappa_ct`
	var hz: float = -4.0 + _rand() * 8.0
	start.x += hz
	start.z += hz
	_pos_gx = start
	_life = LEAF_LIFE
	_timer = _life
	_velocity = Vector3(_rand2() * 2.0, _rand2(), _rand())
	_accel = Vector3(0.0, 0.5 * (0.1 * -_velocity.y), 0.0)
	_spin_x = randf() * TAU
	_spin_z = randf() * TAU
	_sway = randf() * TAU
	_base_scale = LEAF_SCALE


func _setup_snow(crown: Vector3, medium_cedar: bool) -> void:
	var start: Vector3 = jitter(crown, medium_cedar) / GX
	## `eBushYuki_ct`
	var offset: float = -3.0 + 6.0 * _rand()
	start.x += offset
	start.y += offset
	_pos_gx = start
	_life = SNOW_LIFE
	_timer = _life
	_velocity = Vector3(_rand2() * 2.0, _rand(), _rand())
	_accel = Vector3(0.0, -0.125, 0.0)
	_base_scale = SNOW_SCALE


func _attach_leaf_model(family: PlantData.Family) -> void:
	var id: StringName = &"ef_s_tree01_00"
	if family == PlantData.Family.PALM:
		id = &"ef_s_palm"
	elif family == PlantData.Family.CEDAR:
		id = &"ef_s_cedar"
	elif Clock.term_idx() == CHERRY_TERM:
		id = &"ef_f_tree01_00"
	_model = _load_model(id)
	if _model != null and family == PlantData.Family.GOLD:
		_tint(_model, GOLD_TINT)


func _attach_snow_model() -> void:
	_model = _load_model(&"ef_w_yabu01_00")


func _load_model(id: StringName) -> Node3D:
	var paths: PackedStringArray = FieldCatalog.mesh_paths(id)
	if paths.is_empty():
		return null
	var packed: PackedScene = load(paths[0]) as PackedScene
	if packed == null:
		return null
	var inst: Node = packed.instantiate()
	if not (inst is Node3D):
		inst.queue_free()
		return null
	var holder := Node3D.new()
	holder.add_child(inst)
	add_child(holder)
	## Authored × matrix scale → GX; the GLB is already × `PIPELINE_SCALE`.
	var s: float = _base_scale * GX / FieldCatalog.PIPELINE_SCALE
	holder.scale = Vector3(s, s, s)
	_unshade(holder)
	return holder


func _process(delta: float) -> void:
	_acc += delta
	while _acc >= TICK and _timer > 0:
		_acc -= TICK
		_step()
	if _timer <= 0:
		queue_free()
		return
	_sync()


## One 60 Hz tick: `eBushHappa_mv` (leaf) / `eBushYuki_mv` (snow), then the controller's
## `timer--`.
func _step() -> void:
	_velocity += _accel
	_pos_gx += _velocity
	if _kind == Kind.LEAF:
		if _falling:
			_velocity.x *= sqrt(0.95)
			_velocity.z *= sqrt(0.95)
			## `0x662` / `0xA00` on the s16 angle wheel.
			_spin_x += TAU * 0x662 / 65536.0
			_spin_z += TAU * 0x662 / 65536.0
			_sway += TAU * 0xA00 / 65536.0
		else:
			_spin_x += TAU * 0x280 / 65536.0
			_spin_z += TAU * 0x280 / 65536.0
			if _velocity.y <= 0.0:
				_falling = true
				_accel.y = -0.05
	_timer -= 1


func _sync() -> void:
	var at: Vector3 = _pos_gx * GX
	if _kind == Kind.LEAF and _falling:
		var side: float = 2.0 * sin(_sway) * GX
		at += Vector3(side, 0.0, -side)
	global_position = at
	var alpha: float = 1.0
	if _kind == Kind.LEAF:
		alpha = clampf(float(_timer) / LEAF_FADE_TICKS, 0.0, 1.0)
		basis = Basis.from_euler(Vector3(_spin_x, 0.0, _spin_z))
	else:
		var elapsed: float = float(_life - _timer)
		alpha = SNOW_ALPHA * clampf(1.0 - (elapsed - SNOW_FADE_FROM) / (float(_life) - SNOW_FADE_FROM), 0.0, 1.0)
		_billboard()
	_set_alpha(alpha)


func _billboard() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var to: Vector3 = cam.global_position - global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	look_at(global_position + to.normalized(), Vector3.UP)


func _set_alpha(alpha: float) -> void:
	if _model == null:
		return
	for node: Node in _model.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).transparency = 1.0 - alpha


func _unshade(root: Node) -> void:
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat: Material = mi.get_active_material(0)
		if mat is BaseMaterial3D:
			var own: BaseMaterial3D = (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
			own.cull_mode = BaseMaterial3D.CULL_DISABLED
			mi.material_override = own


func _tint(root: Node, color: Color) -> void:
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mat: Material = (node as MeshInstance3D).material_override
		if mat is BaseMaterial3D:
			(mat as BaseMaterial3D).albedo_color = color
