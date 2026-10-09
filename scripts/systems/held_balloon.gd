class_name HeldBalloon
extends RefCounted

## The balloon in hand (`m_player_item_balloon`). It sways on its string: it trails the
## way the hand moves (`balloon_angle.x` eased toward −1200 × the hand's speed along the
## facing), bobs while walking or running (`ballon_add_rot_x`, a counter stepped 400 × speed
## a frame), and turns slowly back and forth about its string without ever settling
## (`balloon_angle.z`: `add_rot_z −= 0.0014 · angle`, `angle += add_rot_z`, held to ±0x800).
## Angles are s16 units as in the decomp; `apply` turns them into a rotation about the hand.

const S16 := TAU / 65536.0
const SWAY_LIMIT := 0x800
const TRAIL := -1200.0
const BOB_STEP := 400.0
const BOB := 1000.0
const EASE_SLOW := 0.0513167
const EASE_FAST := 0.2254033
const MAX_STEP := 2500.0

var angle_x: float = 0.0
var angle_z: float = 0.0
var add_rot_z: float = 30.0
var add_rot_x: float = 0.0
var bob_counter: float = 0.0
var _rest: Transform3D
var _model: Node3D


func setup(model: Node3D) -> void:
	_model = model
	if model != null:
		_rest = model.transform


## `add_calc_short_angle2(&a, target, frac, max, 0)`.
static func ease_angle(a: float, target: float, frac: float, max_step: float) -> float:
	var step: float = clampf((target - a) * frac, -max_step, max_step)
	return a + step


## One frame. `hand_gx` is how far the hand moved this frame (GX), `yaw` the facing,
## `walking` whether the player walks or runs at `speed_gx` a frame.
func step(hand_gx: Vector3, yaw: float, walking: bool, speed_gx: float) -> void:
	var along: float = sin(yaw) * hand_gx.x + cos(yaw) * hand_gx.z
	## The twist about the string.
	add_rot_z -= 0.0014 * angle_z
	angle_z = clampf(angle_z + float(int(add_rot_z)), -SWAY_LIMIT, SWAY_LIMIT)
	## Trailing the hand: slower to come back than to swing out.
	var trail: float = float(int(TRAIL * along))
	var frac: float = EASE_SLOW if absf(trail) < absf(angle_x) else EASE_FAST
	angle_x = ease_angle(angle_x, trail, frac, MAX_STEP)
	var bob_target: float = 0.0
	if walking:
		bob_counter = fposmod(bob_counter + float(int(BOB_STEP * speed_gx)), 65536.0)
		bob_target = BOB * sin(bob_counter * S16)
	add_rot_x = ease_angle(add_rot_x, bob_target, EASE_FAST, MAX_STEP)


func tilt() -> float:
	return (angle_x + add_rot_x) * S16


func twist() -> float:
	return angle_z * S16


## Turn the model about the hand: tilted toward (or away from) the facing, twisted about up.
func apply(yaw: float) -> void:
	if _model == null or not is_instance_valid(_model) or not _model.is_inside_tree():
		return
	_model.transform = _rest
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	var axis: Vector3 = Vector3.UP.cross(forward).normalized()
	var turn := Basis(axis, tilt()) * Basis(Vector3.UP, twist())
	var g: Transform3D = _model.global_transform
	_model.global_transform = Transform3D(turn * g.basis, g.origin)
