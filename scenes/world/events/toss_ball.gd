class_name TossBall
extends Node3D

## A ball thrown at the Sports Fair (`ef_tamaire`): launched at 4.9–6.4 GX a frame, falls at
## 0.15, bounces off the ground (`NA_SE_153`), and when it comes down on its basket's unit it
## rises into the top (60 GX up) and stays. A ball that misses rolls to a stop and is gone after 200
## frames.

const LIFE_FRAMES := 200
const GRAVITY_GX := 0.15
const IN_BASKET_GX := 60.0
## How close (GX) to the basket's centre counts as in.
const BASKET_RADIUS_GX := 22.0
const VISUALS: Array[StringName] = [&"ef_tamaire01_r", &"ef_tamaire01_w"]
## The card as the effect draws it is a little smaller than the generic `ef_*` import.
const BALL_SCALE := 0.7

var team: int = 0
var basket: Vector3 = Vector3.INF
## GX per frame.
var velocity_gx: Vector3 = Vector3.ZERO
var in_basket: bool = false
var _life: int = LIFE_FRAMES
var _steps := FrameStepper.new(DecompTime.FRAME_HZ, 4.0)
var _ground: float = 0.0


func _ready() -> void:
	var pivot: Node3D = GeneratedVisual.attach(self, VISUALS[clampi(team, 0, 1)])
	if pivot != null:
		pivot.scale *= BALL_SCALE
	Audio.play_se(&"152", self)



## `eTamaire_ct`: `angle` toward the basket, `rise` the elevation (radians).
func launch(angle: float, rise: float, speed_gx: float) -> void:
	velocity_gx = Vector3(cos(rise) * sin(angle), sin(rise), cos(rise) * cos(angle)) * speed_gx


func _process(delta: float) -> void:
	if in_basket:
		return
	_steps.add(delta)
	while _steps.next():
		_step()
		if not is_inside_tree():
			return


func _step() -> void:
	var gx: float = FieldCatalog.GX_TO_METERS
	velocity_gx.y -= GRAVITY_GX
	global_position += velocity_gx * gx
	var floor_y: float = _ground_at(global_position)
	if global_position.y < floor_y and basket != Vector3.INF:
		## Landed on the basket's unit (`DUMMY_TURI`): up into the basket it goes.
		var flat := Vector2(global_position.x - basket.x, global_position.z - basket.z)
		if flat.length() < BASKET_RADIUS_GX * gx:
			var base: float = _ground_at(basket) - 3.0 * gx
			global_position = Vector3(basket.x, base + IN_BASKET_GX * gx, basket.z) + Vector3(flat.x, 0.0, flat.y) * 0.4
			in_basket = true
			return
	if global_position.y < floor_y:
		global_position.y = floor_y
		velocity_gx.y *= -0.5
		velocity_gx.x *= 0.5
		velocity_gx.z *= 0.5
		if absf(velocity_gx.y) > 0.5:
			Audio.play_se(&"153", self)
	_life -= 1
	if _life <= 0:
		queue_free()


func _ground_at(pos: Vector3) -> float:
	var world: World = World.find(get_tree()) if get_tree() != null else null
	if world == null or world.layout == null:
		return _ground
	var cell: Vector2i = world.grid.world_to_cell(pos)
	if not world.layout.is_in_bounds(cell):
		return _ground
	## The ground itself, not the basket stand's collision (`GetBgY_AngleS` on the BG).
	_ground = FieldCollision.height_at(world.layout, cell, false) + 3.0 * FieldCatalog.GX_TO_METERS
	return _ground
