class_name TossBall
extends Node3D

## A ball thrown at the Sports Fair (`ef_tamaire`): launched at 4.9–6.4 GX a frame, falls at
## 0.15 GX a frame², bounces off the ground (`NA_SE_153`), and when it comes down on its basket's
## unit it rises into the top (60 GX up) and stays. A ball that misses rolls to a stop and is
## gone after 200 frames (6.7 s). Moves in m/s on `delta`.

## One GX per 1/30 s frame, in m/s.
const FRAME := FieldCatalog.GX_TO_METERS * DecompTime.FRAME_HZ
const LIFETIME := 200.0 / DecompTime.FRAME_HZ
const GRAVITY := 0.15 * FRAME * DecompTime.FRAME_HZ
## A bounce harder than 0.5 GX a frame is heard.
const LOUD_BOUNCE := 0.5 * FRAME
## Landing slower than one frame of gravity is resting on the ground, not a bounce.
const SETTLE_SPEED := GRAVITY / DecompTime.FRAME_HZ
const ROLL_DRAG := 0.69314718 * DecompTime.FRAME_HZ
const IN_BASKET_GX := 60.0
## How close (GX) to the basket's centre counts as in.
const BASKET_RADIUS_GX := 22.0
const VISUALS: Array[StringName] = [&"ef_tamaire01_r", &"ef_tamaire01_w"]
## The card as the effect draws it is a little smaller than the generic `ef_*` import.
const BALL_SCALE := 0.7

var team: int = 0
var basket: Vector3 = Vector3.INF
## m/s.
var velocity: Vector3 = Vector3.ZERO
var in_basket: bool = false
var _life: float = LIFETIME
var _ground: float = 0.0


func _ready() -> void:
	var pivot: Node3D = GeneratedVisual.attach(self, VISUALS[clampi(team, 0, 1)])
	if pivot != null:
		pivot.scale *= BALL_SCALE
	Audio.play_se(&"152", self)



## `eTamaire_ct`: `angle` toward the basket, `rise` the elevation (radians), `speed_gx` in GX a
## frame.
func launch(angle: float, rise: float, speed_gx: float) -> void:
	velocity = Vector3(cos(rise) * sin(angle), sin(rise), cos(rise) * cos(angle)) * speed_gx * FRAME


func _process(delta: float) -> void:
	if in_basket:
		return
	advance(delta)


## `delta` seconds of flight: exact under gravity, then the ground or the basket.
func advance(delta: float) -> void:
	var gx: float = FieldCatalog.GX_TO_METERS
	global_position += velocity * delta + Vector3.DOWN * 0.5 * GRAVITY * delta * delta
	velocity.y -= GRAVITY * delta
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
		if -velocity.y > SETTLE_SPEED:
			velocity.y *= -0.5
			velocity.x *= 0.5
			velocity.z *= 0.5
			if absf(velocity.y) > LOUD_BOUNCE:
				Audio.play_se(&"153", self)
		else:
			## Down on the ground: the halving every frame it touches is a roll that slows by
			## half each 1/30 s.
			velocity.y = 0.0
			var keep: float = exp(-ROLL_DRAG * delta)
			velocity.x *= keep
			velocity.z *= keep
	_life -= delta
	if _life <= 0.0:
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
