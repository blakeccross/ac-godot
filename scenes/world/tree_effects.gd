class_name TreeEffects
extends Node3D

## Falling leaves and winter snow puffs from a shaken tree — `eEC_EFFECT_BUSH_HAPPA`
## (`ef_bush_happa.c`) and `eEC_EFFECT_BUSH_YUKI` (`ef_bush_yuki.c`). Runs on `delta` in
## metres and seconds; the decomp's GX-per-tick numbers are converted where they are
## written (`_speed` / `_accel`).

enum Kind { LEAF, SNOW }

const GX := FieldCatalog.GX_TO_METERS

## `EffectBG_Make_Leafs`: crown of a shaken tree, ±40 GX jitter (±30 for a medium cedar).
const CROWN := 90.0 * GX
const SPREAD := 40.0 * GX
const SPREAD_CEDAR_MED := 30.0 * GX

## `eBushHappa_ct` arg1 4 (6 in cherry season) = shake leaf; scale 0.0106 on authored verts.
const LEAF_SCALE := 0.0106
## 80 ticks, fading over the last 28.
const LEAF_LIFE := 80.0 * DecompTime.TICK_SEC
const LEAF_FADE_TIME := 28.0 * DecompTime.TICK_SEC
## Bush leaves from a step: 60 ticks, 80 when running or tumbling.
const BUSH_LEAF_LIFE := 60.0 * DecompTime.TICK_SEC
const BUSH_LEAF_LIFE_FAST := 80.0 * DecompTime.TICK_SEC
## `eBushYuki_ct`: 60 ticks, scale 0.005, fades after 32.
const SNOW_SCALE := 0.005
const SNOW_LIFE := 60.0 * DecompTime.TICK_SEC
const SNOW_FADE_FROM := 32.0 * DecompTime.TICK_SEC
## −0.125 GX/tick² on snow, −0.05 on a leaf once it starts to fall.
const SNOW_GRAVITY := 0.125 * GX * 3600.0
const LEAF_FALL_GRAVITY := 0.05 * GX * 3600.0
## A falling leaf keeps √0.95 of its sideways speed a tick.
const LEAF_DRAG_PER_SEC := 0.2146  ## 0.95 ^ 30
## Spin while rising (`0x280` a tick) and while falling (`0x662`), sway (`0xA00`): rad/s.
const SPIN_RISE := 0x280 * MathUtil.S16 * 60.0
const SPIN_FALL := 0x662 * MathUtil.S16 * 60.0
const SWAY_RATE := 0xA00 * MathUtil.S16 * 60.0
## Falling leaves sway 2 GX either way.
const SWAY_REACH := 2.0 * GX
const SNOW_ALPHA := 200.0 / 255.0
const CHERRY_TERM := 4
const GOLD_TINT := Color(1.0, 0.86, 0.35)

var _kind: Kind = Kind.LEAF
## m/s and m/s².
var velocity: Vector3 = Vector3.ZERO
var acceleration: Vector3 = Vector3.ZERO
## Where the effect is, before a falling leaf's sway is added (metres).
var drift_position: Vector3 = Vector3.ZERO
var time_left: float = 0.0
var lifetime: float = 0.0
var falling: bool = false
var _spin_x: float = 0.0  ## radians
var _spin_z: float = 0.0
var _sway: float = 0.0
var _model: Node3D
var _base_scale: float = 1.0


## Drop one shake leaf near `crown` (world metres) of a tree in `family`.
static func leaf(host: Node, crown: Vector3, family: PlantData.Family, medium_cedar: bool) -> void:
	var fx := TreeEffects.new()
	fx._kind = Kind.LEAF
	fx._setup_leaf(crown, family, medium_cedar)
	host.add_child(fx)
	fx.global_position = crown
	fx._attach_leaf_model(family)
	fx._sync()


## Winter only: one snow puff (`Make_Leafs` adds a `BUSH_YUKI` per call in winter).
static func snow(host: Node, crown: Vector3, medium_cedar: bool) -> void:
	var fx := TreeEffects.new()
	fx._kind = Kind.SNOW
	fx._setup_snow(crown, medium_cedar)
	host.add_child(fx)
	fx.global_position = crown
	fx._attach_snow_model()
	fx._sync()


## Walk / dash / skid / tumble through a bush: `eBushHappa_ct` with arg1 0–3 draws
## `ef_s_yabu01_00` (`arg1 <= 3`). `pos` is world metres.
static func bush_leaf(host: Node, pos: Vector3, arg1: int) -> void:
	var fx := TreeEffects.new()
	fx._kind = Kind.LEAF
	fx._setup_bush_leaf(pos, arg1)
	host.add_child(fx)
	fx.global_position = pos
	fx._model = fx._load_model(&"ef_s_yabu01_00")
	fx._sync()


## Winter bush snow puff from a step (`eBushYuki_ct` arg1 0).
static func bush_snow(host: Node, pos: Vector3) -> void:
	var fx := TreeEffects.new()
	fx._kind = Kind.SNOW
	fx._setup_bush_snow(pos)
	host.add_child(fx)
	fx.global_position = pos
	fx._attach_snow_model()
	fx._sync()


## `EffectBG_Make_Leafs` position: crown plus a random box around it.
static func jitter(crown: Vector3, medium_cedar: bool) -> Vector3:
	var spread: float = SPREAD_CEDAR_MED if medium_cedar else SPREAD
	return crown + Vector3(_rand2(), _rand2(), _rand2()) * spread


static func _rand() -> float:
	return randf()


## `fqrand2`: [-0.5, 0.5).
static func _rand2() -> float:
	return randf() - 0.5


func _setup_leaf(crown: Vector3, family: PlantData.Family, medium_cedar: bool) -> void:
	## `eBushHappa_ct`: ±4 GX more on X and Z.
	var hz: float = (-4.0 + _rand() * 8.0) * GX
	drift_position = jitter(crown, medium_cedar) + Vector3(hz, 0.0, hz)
	lifetime = LEAF_LIFE
	_launch_leaf(_speed(Vector3(_rand2() * 2.0, _rand2(), _rand())))
	_base_scale = LEAF_SCALE


func _setup_bush_leaf(pos: Vector3, arg1: int) -> void:
	## `eBushHappa_ct`: ±4 GX jitter on X and Z, 60 frames (+20 for arg1 1–3).
	var v_speed: float = 2.5 + _rand() * 1.3
	var hz: float = (-4.0 + _rand() * 8.0) * GX
	drift_position = pos + Vector3(hz, 0.0, hz)
	lifetime = BUSH_LEAF_LIFE if arg1 == 0 else BUSH_LEAF_LIFE_FAST
	match arg1:
		1:
			v_speed *= 1.5
		2:
			v_speed *= 1.8
		3:
			v_speed *= 1.6
	var spread: float = 32.0 if arg1 == 2 or arg1 == 3 else 20.0
	_launch_leaf(_speed(FieldEffects.random_first_speed(v_speed, spread, spread)))
	_base_scale = 0.010199999


func _setup_bush_snow(pos: Vector3) -> void:
	## `eBushYuki_ct` (arg1 0): `random_first_speed(1.5 + rand·1.5, 45, 45)`.
	var y: float = 1.5 + _rand() * 1.5
	var offset: float = (-3.0 + 6.0 * _rand()) * GX
	drift_position = pos + Vector3(offset, offset, 0.0)
	_launch_snow(_speed(FieldEffects.random_first_speed(y, 45.0, 45.0)))


func _setup_snow(crown: Vector3, medium_cedar: bool) -> void:
	## `eBushYuki_ct`: ±3 GX more on X and Y.
	var offset: float = (-3.0 + 6.0 * _rand()) * GX
	drift_position = jitter(crown, medium_cedar) + Vector3(offset, offset, 0.0)
	_launch_snow(_speed(Vector3(_rand2() * 2.0, _rand(), _rand())))


## `eBushHappa_ct`: launch at `v` (m/s), braked upward at a twentieth of the launch climb a
## tick until the leaf turns to fall.
func _launch_leaf(v: Vector3) -> void:
	velocity = v
	acceleration = Vector3(0.0, -0.05 * v.y * DecompTime.TICK_HZ, 0.0)
	time_left = lifetime
	_spin_x = randf() * TAU
	_spin_z = randf() * TAU
	_sway = randf() * TAU


func _launch_snow(v: Vector3) -> void:
	velocity = v
	acceleration = Vector3(0.0, -SNOW_GRAVITY, 0.0)
	lifetime = SNOW_LIFE
	time_left = lifetime
	_base_scale = SNOW_SCALE


## A decomp speed in GX per tick, as m/s.
static func _speed(per_tick: Vector3) -> Vector3:
	return per_tick * GX * DecompTime.TICK_HZ


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
	step(delta)
	if time_left <= 0.0:
		queue_free()
		return
	_sync()


## Advances the effect by `delta` seconds (`eBushHappa_mv` / `eBushYuki_mv`). Integrates in
## closed form, splitting the step where a leaf stops rising, so the path is the same at any
## frame rate.
func step(delta: float) -> void:
	delta = minf(delta, time_left)
	var left: float = delta
	if _kind == Kind.LEAF and not falling:
		var rise: float = 0.0
		if velocity.y > 0.0 and acceleration.y < 0.0:
			rise = minf(velocity.y / -acceleration.y, left)
		elif velocity.y > 0.0:
			rise = left
		_advance(rise)
		left -= rise
		if velocity.y <= 0.0 or is_zero_approx(velocity.y):
			velocity.y = minf(velocity.y, 0.0)
			falling = true
			acceleration.y = -LEAF_FALL_GRAVITY
	_advance(left)
	time_left -= delta


func _advance(dt: float) -> void:
	if dt <= 0.0:
		return
	if _kind == Kind.LEAF and falling:
		## Sideways speed decays by `LEAF_DRAG_PER_SEC` a second; the fall is plain gravity.
		var keep: float = pow(LEAF_DRAG_PER_SEC, dt)
		var reach: float = (keep - 1.0) / log(LEAF_DRAG_PER_SEC)
		drift_position.x += velocity.x * reach
		drift_position.z += velocity.z * reach
		velocity.x *= keep
		velocity.z *= keep
		drift_position.y += velocity.y * dt + 0.5 * acceleration.y * dt * dt
		velocity.y += acceleration.y * dt
		_spin_x += SPIN_FALL * dt
		_spin_z += SPIN_FALL * dt
		_sway += SWAY_RATE * dt
		return
	drift_position += velocity * dt + 0.5 * acceleration * dt * dt
	velocity += acceleration * dt
	if _kind == Kind.LEAF:
		_spin_x += SPIN_RISE * dt
		_spin_z += SPIN_RISE * dt


## How opaque the effect is with `time_left` seconds to go.
func opacity() -> float:
	if _kind == Kind.LEAF:
		return clampf(time_left / LEAF_FADE_TIME, 0.0, 1.0)
	var elapsed: float = lifetime - time_left
	return SNOW_ALPHA * clampf(1.0 - (elapsed - SNOW_FADE_FROM) / (lifetime - SNOW_FADE_FROM), 0.0, 1.0)


func _sync() -> void:
	var at: Vector3 = drift_position
	if _kind == Kind.LEAF and falling:
		var side: float = sin(_sway) * SWAY_REACH
		at += Vector3(side, 0.0, -side)
	global_position = at
	if _kind == Kind.LEAF:
		basis = Basis.from_euler(Vector3(_spin_x, 0.0, _spin_z))
	else:
		_billboard()
	_set_alpha(opacity())


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
