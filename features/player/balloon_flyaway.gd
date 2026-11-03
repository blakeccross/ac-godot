class_name BalloonFlyaway
extends Node3D

## A held balloon let go of (`Ac_Balloon_request_fly` from `Player_actor_setup_Item_Tumble_getup`):
## the player trips, and as they get up the balloon leaves their hand with the pose it had and
## climbs away, accelerating until it is 200 GX above them, where it is gone
## (`Ac_Balloon_request_change_mode_fromFly` → hide). The pocket it came from is emptied.

const GX := FieldCatalog.GX_TO_METERS
## `max_velocity_y = 7`, `gravity = 0.2`: `chase_f(speed.y, 7, 0.5 * 0.2)` a 60 Hz actor tick.
const MAX_SPEED := 7.0 * GX * DecompTime.TICK_HZ
const ACCEL := 0.1 * GX * DecompTime.TICK_HZ * DecompTime.TICK_HZ
## Gone once this far above the player.
const HIDE_HEIGHT := 200.0 * GX
## The tilt comes back upright the way `add_calc_short_angle2(…, 1 − √0.5, …)` does, per 30 fps frame.
const UPRIGHT_FRACTION := 1.0 - 0.70710678

var player: Node3D
var speed: float = 0.0


## Let `held` go from the player's hand. `held` is the model on the hand; a copy keeps its pose.
static func release(held: Node3D, owner_player: Node3D) -> BalloonFlyaway:
	if held == null or not held.is_inside_tree() or owner_player == null:
		return null
	var flyaway := BalloonFlyaway.new()
	flyaway.name = "BalloonFlyaway"
	flyaway.player = owner_player
	var scene: Node = held.get_tree().current_scene
	if scene == null:
		return null
	scene.add_child(flyaway)
	flyaway.global_transform = held.global_transform
	var copy: Node3D = held.duplicate() as Node3D
	flyaway.add_child(copy)
	copy.transform = Transform3D.IDENTITY
	return flyaway


## Speed after `seconds` of climbing from rest.
static func speed_after(seconds: float) -> float:
	return minf(ACCEL * maxf(seconds, 0.0), MAX_SPEED)


## Seconds from letting go to being `height` metres up.
static func seconds_to_rise(height: float) -> float:
	var ramp: float = MAX_SPEED / ACCEL
	var ramp_height: float = 0.5 * ACCEL * ramp * ramp
	if height <= ramp_height:
		return sqrt(2.0 * maxf(height, 0.0) / ACCEL)
	return ramp + (height - ramp_height) / MAX_SPEED


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	speed = minf(speed + ACCEL * delta, MAX_SPEED)
	global_position.y += speed * delta
	var upright: float = 1.0 - pow(1.0 - UPRIGHT_FRACTION, delta * DecompTime.FRAME_HZ)
	var yaw: float = rotation.y
	basis = basis.slerp(Basis.from_euler(Vector3(0.0, yaw, 0.0)), upright).orthonormalized()
	if player == null or not is_instance_valid(player) or global_position.y - player.global_position.y > HIDE_HEIGHT:
		queue_free()
