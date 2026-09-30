class_name HouseWeathervane
extends SkeletonModifier3D

## The fish weathervane on the player's house (`aMHS_actor_draw_before`, joints 3 / 5).
## Joint 3 (`kazamiA`) turns to the wind angle plus the plot side's table angle; joint 5
## (`kazamiB`) spins, its angle dropping by wind power × 1000 each frame
## (`aMHS_actor_move`). The house size picks the axis: RotY for the small house, RotX
## then RotZ(−90°) for the second size, RotX for the larger ones — applied in the
## joint's parent frame, before the joint's own rotation.

const VANE_SUFFIX := "_kazamiA_model"
const SPIN_SUFFIX := "_kazamiB_model"
## `angle_table` in `aMHS_actor_draw_before`, by plot side (`house_idx & 1`).
const SIDE_ANGLE: Array[int] = [0, 0x4000]
const SPIN_PER_FRAME := 1000.0

## 0–3: `obj_s_myhome{size + 1}`.
var house_size: int = 0
## 0 / 1 from the plot index.
var side: int = 0

var _vane: int = -1
var _spin: int = -1
var _vane_rest := Quaternion.IDENTITY
var _spin_rest := Quaternion.IDENTITY
var _spin_angle: float = 0.0


## Adds the modifier to the house visual's skeleton; no-op when it has no weathervane.
static func attach(visual: Node, size: int, plot: int) -> HouseWeathervane:
	for node: Node in visual.find_children("*", "Skeleton3D", true, false):
		var skel := node as Skeleton3D
		for child: Node in skel.get_children():
			if child is HouseWeathervane:
				return child as HouseWeathervane
		var vane := HouseWeathervane.new()
		vane.name = "Weathervane"
		vane.house_size = size
		vane.side = plot & 1
		skel.add_child(vane)
		if vane._vane < 0 and vane._spin < 0:
			vane.queue_free()
			continue
		return vane
	return null


func _ready() -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	for i: int in skel.get_bone_count():
		var bone_name := skel.get_bone_name(i)
		if bone_name.ends_with(VANE_SUFFIX):
			_vane = i
			_vane_rest = skel.get_bone_rest(i).basis.get_rotation_quaternion()
		elif bone_name.ends_with(SPIN_SUFFIX):
			_spin = i
			_spin_rest = skel.get_bone_rest(i).basis.get_rotation_quaternion()


func _physics_process(delta: float) -> void:
	_spin_angle = fposmod(_spin_angle - Wind.power() * SPIN_PER_FRAME * delta * 60.0, 65536.0)


## The draw callback's extra rotation for binangle `angle`.
static func turn(size: int, angle: float) -> Quaternion:
	var rad: float = angle / 65536.0 * TAU
	match size:
		0:
			return Quaternion(Vector3.UP, rad)
		1:
			return Quaternion(Vector3.RIGHT, rad) * Quaternion(Vector3.BACK, -PI * 0.5)
	return Quaternion(Vector3.RIGHT, rad)


func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	if _vane >= 0:
		var angle: float = float((Wind.angle_s() + SIDE_ANGLE[side]) & 0xFFFF)
		skel.set_bone_pose_rotation(_vane, turn(house_size, angle) * _vane_rest)
	if _spin >= 0:
		skel.set_bone_pose_rotation(_spin, turn(house_size, _spin_angle) * _spin_rest)
