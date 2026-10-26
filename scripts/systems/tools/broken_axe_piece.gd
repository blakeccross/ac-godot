class_name BrokenAxePiece
extends Node3D

## `ef_break_axe`: the two halves of a worn-out axe (`ef_axe1` the head, `ef_axe2` the
## handle) thrown back over the player's shoulder at `AXE_BREAK1` frame 15. Each tumbles under
## gravity, bounces off the ground at 0.6 with its spin halved, turns back off a rise, sinks
## slowly in water, and fades over its last half-second. Runs on `delta` in metres: the flight
## is exact within a frame and a bounce happens at the moment it meets the ground.

const GX := FieldCatalog.GX_TO_METERS
const VISUAL: Array[StringName] = [&"ef_axe1", &"ef_axe2"]
## 0.25 GX/tick².
const GRAVITY := 0.25 * GX * 3600.0
const BOUNCE := 0.6
## Fades over its last 30 ticks.
const FADE_TIME := 30.0 * DecompTime.TICK_SEC
## Ignores the ground for its first 5 ticks (it starts below the player's shoulder line).
const GROUND_GRACE := 5.0 * DecompTime.TICK_SEC
## In water: speed × 0.8 and spin × √0.9 every tick.
const WATER_DRAG := 13.388  ## −ln(0.8) · 60
const WATER_SPIN_DRAG := 3.161  ## −ln(√0.9) · 60
const SCALE := 0.01
## Resting height over the ground by piece (`offset.y += 10 / 15` GX).
const LIFT: Array[float] = [10.0 * GX, 15.0 * GX]
## `tx / ty / tz` from the player, in the player's frame (GX).
const START: Array[Vector3] = [Vector3(-17.0, 34.0, 20.0), Vector3(17.0, 27.0, -4.0)]
const S16 := TAU / 65536.0

var which: int = 0
## Seconds since it was thrown, and how long it lasts (70–88 ticks).
var age: float = 0.0
var lifetime: float = 70.0 / 60.0
var pos: Vector3 = Vector3.ZERO
## m/s.
var vel: Vector3 = Vector3.ZERO
var yaw: float = 0.0
var spin_x: float = 0.0
var spin_z: float = 0.0
## rad/s.
var rate_x: float = 0.0
var rate_z: float = 0.0
## Ground height under a point (metres, `NAN` = none) and whether it is water; both
## overridable for tests.
var ground_at: Callable
var water_at: Callable
var _card: Node3D
var _materials: Array[StandardMaterial3D] = []


## `eSwing_Axe_init` with `arg1` 3: both pieces from the player standing at `at`.
static func spawn_pair(host: Node, at: Vector3, player_yaw: float, rng: RandomNumberGenerator) -> Array[BrokenAxePiece]:
	var out: Array[BrokenAxePiece] = []
	if host == null:
		return out
	for i: int in 2:
		var p := BrokenAxePiece.new()
		p.setup(i, at, player_yaw, rng)
		host.add_child(p)
		p.global_position = p.pos
		out.append(p)
	return out


## `eBreak_Axe_ct`.
func setup(p_which: int, at: Vector3, player_yaw: float, rng: RandomNumberGenerator) -> void:
	which = clampi(p_which, 0, 1)
	lifetime = float(rng.randi_range(0, 9) * 2 + 70) / 60.0
	var s: Vector3 = START[which]
	var fwd := Vector3(sin(player_yaw), 0.0, cos(player_yaw))
	var side := Vector3(cos(player_yaw), 0.0, -sin(player_yaw))
	var along: float = s.z if which == 0 else s.x
	var across: float = s.x if which == 0 else s.z
	pos = at + (fwd * along + side * across + Vector3(0.0, s.y, 0.0)) * GX
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
	## GX a tick → m/s.
	vel = Vector3(speed_xz * sin(throw), speed_y, speed_xz * cos(throw)) * GX * 60.0
	yaw = player_yaw + deg_to_rad(-77.0)
	spin_x = deg_to_rad(-20.0)
	spin_z = 0.0
	rate_x = float(rng.randi() & 0xFFF) * S16 * 60.0
	rate_z = float(rng.randi() & 0xFFF) * S16 * 60.0


## Opaque until its last `FADE_TIME` (`calc_adjust_proc(timer, 0, 30, 0, 255)`).
static func alpha_at(time_left: float) -> float:
	return clampf(time_left / FADE_TIME, 0.0, 1.0)


func _ready() -> void:
	if not ground_at.is_valid():
		ground_at = _field_ground
	if not water_at.is_valid():
		water_at = _field_water
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
	_redraw()


func _process(delta: float) -> void:
	advance(delta)
	if age >= lifetime:
		queue_free()
		return
	_redraw()


## `eBreak_Axe_mv` over `delta` seconds.
func advance(delta: float) -> void:
	var left: float = minf(delta, maxf(lifetime - age, 0.0))
	## A bounce splits the frame; a few is plenty.
	for _i: int in 4:
		if left <= 0.0:
			break
		left -= _fly(left)
	age += delta
	spin_x += rate_x * delta
	spin_z += rate_z * delta


## Flies for up to `dt` seconds; returns how long it actually flew (less if it bounced).
func _fly(dt: float) -> float:
	var ground: float = _lifted(ground_at.call(pos))
	var water: bool = bool(water_at.call(pos))
	var checking: bool = age >= GROUND_GRACE and not is_nan(ground)
	if checking and water and pos.y < ground:
		## Sinking: speed and spin drain away.
		var keep: float = exp(-WATER_DRAG * dt)
		vel *= keep
		rate_x *= exp(-WATER_SPIN_DRAG * dt)
		rate_z *= exp(-WATER_SPIN_DRAG * dt)
	var next: Vector3 = pos + vel * dt + Vector3(0.0, -0.5 * GRAVITY * dt * dt, 0.0)
	if checking and not water and pos.y >= ground and next.y < ground:
		## Meets the ground part-way through: move there, bounce, and report the time used.
		var t: float = _time_to_height(pos.y - ground, vel.y, dt)
		pos += vel * t + Vector3(0.0, -0.5 * GRAVITY * t * t, 0.0)
		pos.y = ground
		var vy: float = vel.y - GRAVITY * t
		vel = Vector3(vel.x * BOUNCE, -vy * BOUNCE, vel.z * BOUNCE)
		rate_x *= 0.5
		rate_z *= 0.5
		return maxf(t, 1e-4)
	var ahead: float = _lifted(ground_at.call(next))
	if checking and not water and not is_nan(ahead) and next.y < ahead and next.y >= ground:
		## Ran into a rise: back off and turn round.
		vel.x *= -BOUNCE
		vel.z *= -BOUNCE
		vel.y -= GRAVITY * dt
		return dt
	pos = next
	vel.y -= GRAVITY * dt
	return dt


## When something `height` above the ground, moving up at `vy` under `GRAVITY`, comes down
## to it, clamped to `dt`.
func _time_to_height(height: float, vy: float, dt: float) -> float:
	var disc: float = vy * vy + 2.0 * GRAVITY * height
	if disc < 0.0:
		return dt
	return clampf((vy + sqrt(disc)) / GRAVITY, 0.0, dt)


func _lifted(y: Variant) -> float:
	var g: float = float(y)
	return NAN if is_nan(g) else g + LIFT[which]


func _redraw() -> void:
	global_position = pos
	basis = Basis(Vector3.UP, yaw) * Basis.from_euler(Vector3(spin_x, 0.0, spin_z))
	if _card != null:
		_card.scale = Vector3.ONE * SCALE * GX / FieldCatalog.PIPELINE_SCALE
	var a: float = alpha_at(lifetime - age)
	for mat: StandardMaterial3D in _materials:
		mat.albedo_color.a = a


func _field_ground(at: Vector3) -> float:
	var world := World.find(get_tree()) if is_inside_tree() else null
	if world == null or world.layout == null or world.grid == null:
		return NAN
	var y: float = FieldCollision.ground_y_at(world.layout, world.grid, at)
	return y if FieldCollision.has_floor(y) else NAN


func _field_water(at: Vector3) -> bool:
	var world := World.find(get_tree()) if is_inside_tree() else null
	if world == null or world.grid == null:
		return false
	var attr: int = FieldCollision.unit_attr_at(world.layout, world.grid, at)
	return attr >= 0 and FieldCatalog.is_water_attr(attr)
