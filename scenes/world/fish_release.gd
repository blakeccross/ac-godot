class_name FishRelease
extends Node3D

## A fish let go from the pockets, flying into the water (`ac_gyo_release`). It arcs from
## the player's feet to the water point, noses over flat as it falls, and on reaching the
## surface leaves a fading shadow swimming on (`GYO_KAGE`) with the splash SE 0x437. The
## splash ring (`TURI_HAMON`) is not drawn: fishing has no ripple effect yet either.

const SCENE_PATH := "res://scenes/world/fish_release.tscn"
const SPLASH_SE := &"437"

## `exist_flag`: cleared once it is in the water or gone (the player stops watching).
var exist: bool = true
var fish: FishData = null
## World position in metres → is it water; world position → water surface y (metres).
var is_water: Callable = Callable()
var water_y: Callable = Callable()
## Where the fading shadow goes (`FishSchool`); null leaves none.
var school: FishSchool = null

var _pos_gx: Vector3 = Vector3.ZERO
var _vel_gx: Vector3 = Vector3.ZERO
var _yaw: float = 0.0
var _tilt: float = 0.0
var _ticks: int = 0
var _been_in_water: bool = false
var _revert_timer: int = 0
var _visual: HeldFish = null
var _steps := FrameStepper.new(DecompTime.TICK_HZ, 8.0)


## Throw `p_fish` from `from` (metres) at the water point `water` (metres, y on the surface).
static func throw(parent: Node, p_fish: FishData, from: Vector3, water: Vector3) -> FishRelease:
	var node := (load(SCENE_PATH) as PackedScene).instantiate() as FishRelease
	node.fish = p_fish
	node._pos_gx = from / FieldCatalog.GX_TO_METERS
	var water_gx: Vector3 = water / FieldCatalog.GX_TO_METERS
	node._vel_gx = CreatureRelease.launch_velocity(node._pos_gx, water_gx)
	node._yaw = atan2(water_gx.x - node._pos_gx.x, water_gx.z - node._pos_gx.z)
	var world := World.find(parent.get_tree()) if parent.is_inside_tree() else null
	if world != null:
		node.bind_world(world)
	parent.add_child(node)
	return node


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
	_steps.add(delta)
	while exist and _steps.next():
		tick()


## One `aGYR_actor_move`.
func tick() -> void:
	var last: Vector3 = _pos_gx
	var moved: Array[Vector3] = CreatureRelease.step(_pos_gx, _vel_gx)
	_pos_gx = moved[0]
	_vel_gx = moved[1]
	var at: Vector3 = _pos_gx * FieldCatalog.GX_TO_METERS
	var wet: bool = is_water.is_valid() and bool(is_water.call(at))
	_revert_timer = maxi(_revert_timer - 1, 0)
	## Once over water it may not drift back out onto the bank.
	if wet:
		if not _been_in_water:
			_been_in_water = true
			_revert_timer = 3
	elif _been_in_water and _revert_timer <= 0:
		_pos_gx.x = last.x
		_pos_gx.z = last.z
	_tilt = move_toward(_tilt, PI * 0.5, CreatureRelease.TILT_STEP)
	_ticks += 1
	if _ticks > CreatureRelease.LIFE:
		_finish()
		return
	if wet and water_y.is_valid():
		var surface_gx: float = float(water_y.call(at)) / FieldCatalog.GX_TO_METERS
		if surface_gx >= _pos_gx.y:
			_enter_water()
			return
	_apply()


func position_gx() -> Vector3:
	return _pos_gx


## `aGYR_in_water_move`.
func _enter_water() -> void:
	Audio.play_se(SPLASH_SE, self)
	if school != null and fish != null:
		school.add_puff_at(_pos_gx * FieldCatalog.GX_TO_METERS, _yaw, fish.size_class)
	_finish()


func _finish() -> void:
	exist = false
	queue_free()


## `aGYR_actor_draw`: no yaw of its own — tilted flat by `angle_xz` and stretched 1.2×
## across, shrinking past tick 140.
func _apply() -> void:
	global_position = _pos_gx * FieldCatalog.GX_TO_METERS
	var basis := Basis(Vector3.RIGHT, -_tilt) * Basis(Vector3.BACK, _tilt)
	var s: float = CreatureRelease.SCALE_RATIO * CreatureRelease.shrink(_ticks)
	global_basis = basis * Basis.from_scale(Vector3(CreatureRelease.WIDTH * s, s, s))
