class_name BrokenAxePiece
extends Node3D

## `ef_break_axe`: the two halves of a worn-out axe (`ef_axe1` the head, `ef_axe2` the
## handle) thrown back over the player's shoulder at `AXE_BREAK1` frame 15. Each tumbles under
## gravity (0.25 GX a tick), bounces off the ground at 0.6 with its spin halved, turns back off
## a rise, sinks slowly in water, and fades over its last 30 ticks. GX at 60 Hz.

const VISUAL: Array[StringName] = [&"ef_axe1", &"ef_axe2"]
const GRAVITY := 0.25
const BOUNCE := 0.6
const FADE := 30
const SCALE := 0.01
## Resting height over the ground by piece (`offset.y += 10 / 15`).
const LIFT: Array[float] = [10.0, 15.0]
## `tx / ty / tz` from the player, in the player's frame.
const START: Array[Vector3] = [Vector3(-17.0, 34.0, 20.0), Vector3(17.0, 27.0, -4.0)]
const S16 := TAU / 65536.0

var which: int = 0
var timer: int = 70
var life: int = 70
var pos_gx: Vector3 = Vector3.ZERO
var vel: Vector3 = Vector3.ZERO
var yaw: float = 0.0
var spin_x: float = 0.0
var spin_z: float = 0.0
var rate_x: float = 0.0
var rate_z: float = 0.0
## Ground under the piece (GX, `NAN` = none) and whether it is water; both overridable for tests.
var ground_gx: Callable
var water_at: Callable
var _prev_ground: float = NAN
var _ground: float = NAN
var _card: Node3D
var _materials: Array[StandardMaterial3D] = []
var _steps := FrameStepper.new(DecompTime.TICK_HZ, 8.0)


## `eSwing_Axe_init` with `arg1` 3: both pieces from the player standing at `at`.
static func spawn_pair(host: Node, at: Vector3, player_yaw: float, rng: RandomNumberGenerator) -> Array[BrokenAxePiece]:
	var out: Array[BrokenAxePiece] = []
	if host == null:
		return out
	for i: int in 2:
		var p := BrokenAxePiece.new()
		p.setup(i, at / FieldCatalog.GX_TO_METERS, player_yaw, rng)
		host.add_child(p)
		p.global_position = p.pos_gx * FieldCatalog.GX_TO_METERS
		out.append(p)
	return out


## `eBreak_Axe_ct`.
func setup(p_which: int, at_gx: Vector3, player_yaw: float, rng: RandomNumberGenerator) -> void:
	which = clampi(p_which, 0, 1)
	life = rng.randi_range(0, 9) * 2 + 70
	timer = life
	var s: Vector3 = START[which]
	var fwd := Vector3(sin(player_yaw), 0.0, cos(player_yaw))
	var side := Vector3(cos(player_yaw), 0.0, -sin(player_yaw))
	var along: float = s.z if which == 0 else s.x
	var across: float = s.x if which == 0 else s.z
	pos_gx = at_gx + fwd * along + side * across + Vector3(0.0, s.y, 0.0)
	var throw: float = player_yaw + PI
	var speed_xz: float
	var speed_y: float
	if which == 0:
		throw += deg_to_rad(40.0 + rng.randf() * 20.0)
		speed_xz = 0.25 + rng.randf() * 0.75
		speed_y = 4.0 + rng.randf() * 1.0
	else:
		throw += deg_to_rad(20.0 + rng.randf() * 20.0)
		speed_xz = 0.75 + rng.randf() * 0.5
		speed_y = 3.75 + rng.randf() * 1.5
	vel = Vector3(speed_xz * sin(throw), speed_y, speed_xz * cos(throw))
	yaw = player_yaw + deg_to_rad(-77.0)
	spin_x = deg_to_rad(-20.0)
	spin_z = 0.0
	rate_x = float(rng.randi() & 0xFFF) * S16
	rate_z = float(rng.randi() & 0xFFF) * S16


## `calc_adjust_proc(timer, 0, 30, 0, 255)`.
static func alpha_at(t: int) -> float:
	return clampf(float(t) / FADE, 0.0, 1.0)


func _ready() -> void:
	if not ground_gx.is_valid():
		ground_gx = _field_ground
	if not water_at.is_valid():
		water_at = _field_water
	_ground = _lifted(ground_gx.call(pos_gx))
	_card = GeneratedVisual.instantiate_raw(VISUAL[which])
	if _card != null:
		add_child(_card)
		for node: Node in _card.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			for i: int in mi.get_surface_override_material_count():
				var mat := mi.get_active_material(i) as StandardMaterial3D
				if mat == null:
					continue
				var own := mat.duplicate() as StandardMaterial3D
				own.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mi.set_surface_override_material(i, own)
				_materials.append(own)
	_draw()


func _process(delta: float) -> void:
	_steps.add(delta)
	while _steps.next():
		step()
		timer -= 1
		if timer <= 0:
			queue_free()
			return
	_draw()


## `eBreak_Axe_mv`, one tick.
func step() -> void:
	var water: bool = bool(water_at.call(pos_gx))
	var before_y: float = pos_gx.y
	_prev_ground = _ground
	_ground = _lifted(ground_gx.call(pos_gx))
	vel.y -= GRAVITY
	pos_gx += vel
	spin_x += rate_x
	spin_z += rate_z
	if timer > life - 5 or is_nan(_ground):
		return
	if pos_gx.y < _ground and water:
		vel *= 0.8
		rate_x = lerpf(rate_x, 0.0, 1.0 - sqrt(0.9))
		rate_z = lerpf(rate_z, 0.0, 1.0 - sqrt(0.9))
	if pos_gx.y < _ground and before_y >= _ground and vel.y < 0.0 and not water:
		pos_gx.y = _ground
		vel = Vector3(vel.x * BOUNCE, -vel.y * BOUNCE, vel.z * BOUNCE)
		rate_x *= 0.5
		rate_z *= 0.5
	if not is_nan(_prev_ground) and pos_gx.y < _ground and pos_gx.y >= _prev_ground:
		pos_gx -= vel
		vel.x *= -BOUNCE
		vel.z *= -BOUNCE


func _lifted(y: Variant) -> float:
	var g: float = float(y)
	return NAN if is_nan(g) else g + LIFT[which]


func _draw() -> void:
	global_position = pos_gx * FieldCatalog.GX_TO_METERS
	basis = Basis(Vector3.UP, yaw) * Basis.from_euler(Vector3(spin_x, 0.0, spin_z))
	if _card != null:
		_card.scale = Vector3.ONE * SCALE * FieldCatalog.GX_TO_METERS / FieldCatalog.PIPELINE_SCALE
	var a: float = alpha_at(timer)
	for mat: StandardMaterial3D in _materials:
		mat.albedo_color.a = a


func _field_ground(at_gx: Vector3) -> float:
	var world := World.find(get_tree()) if is_inside_tree() else null
	if world == null or world.layout == null or world.grid == null:
		return NAN
	var y: float = FieldCollision.ground_y_at(world.layout, world.grid, at_gx * FieldCatalog.GX_TO_METERS)
	return y / FieldCatalog.GX_TO_METERS if FieldCollision.has_floor(y) else NAN


func _field_water(at_gx: Vector3) -> bool:
	var world := World.find(get_tree()) if is_inside_tree() else null
	if world == null or world.grid == null:
		return false
	var attr: int = FieldCollision.unit_attr_at(world.layout, world.grid, at_gx * FieldCatalog.GX_TO_METERS)
	return attr >= 0 and FieldCatalog.is_water_attr(attr)
