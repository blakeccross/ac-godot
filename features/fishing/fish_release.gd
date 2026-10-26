class_name FishRelease
extends Node3D

## A fish let go from the pockets, flying into the water (`ac_gyo_release`). It arcs from
## the player's feet to the water point, noses over flat as it falls, and on reaching the
## surface leaves a ring (`TURI_HAMON` 3) and a fading shadow swimming on (`GYO_KAGE`) with
## the splash SE 0x437. Runs on `delta` in metres: the arc is closed form and it splashes at
## the moment it reaches the surface.

const SCENE_PATH := "res://features/fishing/fish_release.tscn"
const SPLASH_SE := &"437"
const GX := FieldCatalog.GX_TO_METERS
## `CreatureRelease` speeds are GX per 30 fps frame moved half a frame a tick, under −0.25 a
## tick: as m/s and m/s².
const SPEED := GX * 30.0
const GRAVITY := -CreatureRelease.GRAVITY * 60.0 * 30.0 * GX
## Noses over 0x800 a tick; gone after 160 ticks.
const TILT_RATE := CreatureRelease.TILT_STEP * 60.0
const LIFETIME := CreatureRelease.LIFE * DecompTime.TICK_SEC
## Once over water it may not drift back out onto the bank after 3 ticks.
const BANK_GRACE := 3.0 * DecompTime.TICK_SEC
## `exist_flag`: cleared once it is in the water or gone (the player stops watching).
var exist: bool = true
var fish: FishData = null
## World position in metres → is it water; world position → water surface y (metres).
var is_water: Callable = Callable()
var water_y: Callable = Callable()
## Where the fading shadow goes (`FishSchool`); null leaves none.
var school: FishSchool = null
## Seconds since the throw.
var age: float = 0.0

## Metres and m/s.
var _pos: Vector3 = Vector3.ZERO
var _vel: Vector3 = Vector3.ZERO
var _yaw: float = 0.0
var _tilt: float = 0.0
var _wet_since: float = -1.0
var _visual: HeldFish = null


## Throw `p_fish` from `from` (metres) at the water point `water` (metres, y on the surface).
static func throw(parent: Node, p_fish: FishData, from: Vector3, water: Vector3) -> FishRelease:
	var node := (load(SCENE_PATH) as PackedScene).instantiate() as FishRelease
	node.fish = p_fish
	node.aim(from, water)
	var world := World.find(parent.get_tree()) if parent.is_inside_tree() else null
	if world != null:
		node.bind_world(world)
	parent.add_child(node)
	return node


## Start at `from` thrown toward `water` (both metres), `aGYR_ct`'s launch.
func aim(from: Vector3, water: Vector3) -> void:
	_pos = from
	_vel = CreatureRelease.launch_velocity(from / GX, water / GX) * SPEED
	_yaw = atan2(water.x - from.x, water.z - from.z)


func bind_world(world: World) -> void:
	school = world.fish
	var layout: WorldData = world.layout
	var grid: WorldGrid = world.grid
	is_water = func(at: Vector3) -> bool:
		var attr: int = FieldCollision.unit_attr_at(layout, grid, at)
		return attr >= 0 and FieldCatalog.is_water_attr(attr)
	water_y = func(at: Vector3) -> float: return world.fish.surface_at(at)


func _ready() -> void:
	_visual = HeldFish.create(fish)
	if _visual != null:
		_visual.billboard = false
		_visual.position = Vector3.ZERO
		add_child(_visual)
	_apply()


func _physics_process(delta: float) -> void:
	if exist:
		advance(delta)


## `aGYR_actor_move` over `delta` seconds.
func advance(delta: float) -> void:
	var dt: float = minf(delta, LIFETIME - age)
	var next: Vector3 = _pos + _vel * dt + Vector3(0.0, -0.5 * GRAVITY * dt * dt, 0.0)
	var wet: bool = is_water.is_valid() and bool(is_water.call(next))
	if wet and _wet_since < 0.0:
		_wet_since = age
	elif not wet and _wet_since >= 0.0 and age - _wet_since >= BANK_GRACE:
		next.x = _pos.x
		next.z = _pos.z
	if wet and water_y.is_valid():
		var surface: float = float(water_y.call(next))
		if surface >= next.y:
			## Reaches the surface part-way through the frame: splash there.
			var t: float = _time_to(_pos.y - surface, _vel.y, dt)
			_pos += _vel * t + Vector3(0.0, -0.5 * GRAVITY * t * t, 0.0)
			_pos.y = surface
			_enter_water()
			return
	_pos = next
	_vel.y -= GRAVITY * dt
	_tilt = move_toward(_tilt, PI * 0.5, TILT_RATE * dt)
	age += delta
	if age >= LIFETIME:
		_finish()
		return
	_apply()


## When something `height` above the surface, moving up at `vy`, comes down to it (≤ `dt`).
static func _time_to(height: float, vy: float, dt: float) -> float:
	var disc: float = vy * vy + 2.0 * GRAVITY * height
	if disc < 0.0:
		return dt
	return clampf((vy + sqrt(disc)) / GRAVITY, 0.0, dt)


## Test-only: no in-game callers; kept for tests.
func position_gx() -> Vector3:
	return _pos / GX


## `aGYR_in_water_move`.
func _enter_water() -> void:
	Audio.play_se(SPLASH_SE, self)
	FootstepEffects.ripple(_pos, 3)
	if school != null and fish != null:
		school.add_puff_at(_pos, _yaw, fish.size_class)
	_finish()


func _finish() -> void:
	exist = false
	queue_free()


## `aGYR_actor_draw`: no yaw of its own — tilted flat by `angle_xz` and stretched 1.2×
## across, shrinking past tick 140.
func _apply() -> void:
	global_position = _pos
	var basis := Basis(Vector3.RIGHT, -_tilt) * Basis(Vector3.BACK, _tilt)
	var s: float = CreatureRelease.SCALE_RATIO * CreatureRelease.shrink(int(age * 60.0))
	global_basis = basis * Basis.from_scale(Vector3(CreatureRelease.WIDTH * s, s, s))
