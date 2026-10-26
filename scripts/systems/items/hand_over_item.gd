class_name HandOverItem
extends Node3D

## Floating item card during NPC ↔ player hand-off (`ac_handOverItem`).
## Follows the master's LARM2 with decomp trans/scale keyframes; draw is world-
## translated with identity rotation (`aHOI_actor_draw`).

enum Mode {
	NONE,
	TRANSFER,
	TRANS_WAIT,
	PUTAWAY,
}

## `aHOI_anime_proc`: anm_cnt += 0.5 at 60 Hz → 30 units/sec.
const ANM_RATE := 30.0
const ARM_BONE := "joint_16"
const ARM_BONE_INDEX := 16
## `Matrix_RotateY(master.yaw + DEG2SHORT_ANGLE(-90))` before local trans.
const YAW_BIAS := -PI * 0.5

## Transfer local offsets (`transfer_data` / `trans_wait_data` / `putaway_data`).
const TRANSFER_KEYS: Array[Dictionary] = [
	{"frame": 0.0, "pos": Vector3(9.0, 0.0, 0.0)},
	{"frame": 17.0, "pos": Vector3(9.0, 0.0, 0.0)},
	{"frame": 31.0, "pos": Vector3(14.0, -9.5, 6.0)},
	{"frame": 39.0, "pos": Vector3(14.0, -9.5, 6.0)},
]
const WAIT_POS := Vector3(14.0, -9.5, 6.0)
const PUTAWAY_KEYS: Array[Dictionary] = [
	{"frame": 0.0, "pos": Vector3(14.0, -9.5, 6.0)},
	{"frame": 13.0, "pos": Vector3(9.0, 0.0, 0.0)},
	{"frame": 31.0, "pos": Vector3(9.0, 0.0, 0.0)},
]
## Scale keys (`transfer_data` / `putaway_data`).
const TRANSFER_SCALE: Array[Dictionary] = [
	{"frame": 0.0, "scale": 0.0},
	{"frame": 17.0, "scale": 0.0},
	{"frame": 35.0, "scale": 1.0},
]
const PUTAWAY_SCALE: Array[Dictionary] = [
	{"frame": 0.0, "scale": 1.0},
	{"frame": 13.0, "scale": 0.0},
]

const MODE_MAX_ANM: Dictionary = {
	Mode.NONE: 1.0,
	Mode.TRANSFER: 39.0,
	Mode.TRANS_WAIT: 17.0,
	Mode.PUTAWAY: 31.0,
}

var mode: Mode = Mode.NONE
var item_id: StringName = &""
var visual_id: StringName = &""
var _master: Node3D
var _mesh: Node3D
var _anm_cnt: float = 0.0
var _base_scale: float = 1.0
var _chase: bool = false


static func visual_for(item: StringName) -> StringName:
	## Prefer the same `obj_item_*` card `mNT_get_itemTableNo` would pick.
	if item == &"":
		return &""
	var hit: StringName = FieldCatalog.item_visual(item)
	if hit != &"" and not FieldCatalog.mesh_paths(hit).is_empty():
		return hit
	return &""


static func spawn(parent: Node, item: StringName) -> HandOverItem:
	if parent == null or item == &"":
		return null
	var visual: StringName = visual_for(item)
	if visual == &"":
		return null
	var card: Node3D = GeneratedVisual.instantiate_raw(visual)
	if card == null:
		return null
	var prop := HandOverItem.new()
	prop.name = "HandOverItem"
	prop.item_id = item
	prop.visual_id = visual
	prop._base_scale = FieldCatalog.actor_uniform_scale_for(visual)
	prop._mesh = card
	card.name = "Card"
	parent.add_child(prop)
	prop.add_child(card)
	prop.visible = false
	prop.scale = Vector3.ZERO
	return prop


func set_master(actor: Node3D, chase: bool = false) -> void:
	_master = actor
	_chase = chase


func begin_mode(next: Mode) -> void:
	mode = next
	_anm_cnt = 0.0
	if next == Mode.TRANSFER or next == Mode.TRANS_WAIT or next == Mode.PUTAWAY:
		visible = true


func finish() -> void:
	mode = Mode.NONE
	queue_free()


func _process(delta: float) -> void:
	if mode == Mode.NONE or _master == null or not is_instance_valid(_master):
		return
	var max_anm: float = float(MODE_MAX_ANM.get(mode, 1.0))
	_anm_cnt = minf(_anm_cnt + delta * ANM_RATE, max_anm)
	var local_gx: Vector3 = _sample_trans()
	var anim_scale: float = _sample_scale()
	var hand: Vector3 = _hand_world(_master)
	var yaw: float = _master_yaw(_master)
	var offset: Vector3 = Basis(Vector3.UP, yaw + YAW_BIAS) * (local_gx * FieldCatalog.GX_TO_METERS)
	var target: Vector3 = hand + offset
	if _chase:
		global_position = global_position.lerp(target, clampf(delta * 12.0, 0.0, 1.0))
		if global_position.distance_squared_to(target) < 0.0004:
			_chase = false
			global_position = target
	else:
		global_position = target
	## World-axis draw (`Matrix_translate` load) — keep authored card orientation.
	global_rotation = Vector3.ZERO
	var s: float = anim_scale * _base_scale
	scale = Vector3.ONE * s
	visible = s > 0.0001


func _sample_trans() -> Vector3:
	match mode:
		Mode.TRANSFER:
			return _lerp_pos(TRANSFER_KEYS, _anm_cnt)
		Mode.TRANS_WAIT:
			return WAIT_POS
		Mode.PUTAWAY:
			return _lerp_pos(PUTAWAY_KEYS, _anm_cnt)
		_:
			return Vector3.ZERO


func _sample_scale() -> float:
	match mode:
		Mode.TRANSFER:
			return _lerp_scale(TRANSFER_SCALE, _anm_cnt)
		Mode.TRANS_WAIT:
			return 1.0
		Mode.PUTAWAY:
			return _lerp_scale(PUTAWAY_SCALE, _anm_cnt)
		_:
			return 0.0


static func _lerp_pos(keys: Array[Dictionary], frame: float) -> Vector3:
	if keys.is_empty():
		return Vector3.ZERO
	var i: int = keys.size() - 2
	while i > 0 and frame <= float(keys[i]["frame"]):
		i -= 1
	var a: Dictionary = keys[i]
	var b: Dictionary = keys[mini(i + 1, keys.size() - 1)]
	var span: float = float(b["frame"]) - float(a["frame"])
	var t: float = 0.0 if span <= 0.0001 else clampf((frame - float(a["frame"])) / span, 0.0, 1.0)
	return (a["pos"] as Vector3).lerp(b["pos"] as Vector3, t)


static func _lerp_scale(keys: Array[Dictionary], frame: float) -> float:
	if keys.is_empty():
		return 0.0
	var i: int = keys.size() - 2
	while i > 0 and frame <= float(keys[i]["frame"]):
		i -= 1
	var a: Dictionary = keys[i]
	var b: Dictionary = keys[mini(i + 1, keys.size() - 1)]
	var span: float = float(b["frame"]) - float(a["frame"])
	var t: float = 0.0 if span <= 0.0001 else clampf((frame - float(a["frame"])) / span, 0.0, 1.0)
	return lerpf(float(a["scale"]), float(b["scale"]), t)


static func _hand_world(actor: Node3D) -> Vector3:
	## LARM2 joint origin — same matrix `aNPC_set_left_hand_item` / player Larm2 capture.
	if actor == null:
		return Vector3.ZERO
	var skeleton: Skeleton3D = HeldTool.find_skeleton(actor)
	if skeleton == null:
		return actor.global_position + Vector3(0.0, 0.9, 0.0)
	var bone := ARM_BONE
	if skeleton.find_bone(bone) < 0:
		if skeleton.get_bone_count() <= ARM_BONE_INDEX:
			return actor.global_position + Vector3(0.0, 0.9, 0.0)
		bone = skeleton.get_bone_name(ARM_BONE_INDEX)
	var idx: int = skeleton.find_bone(bone)
	if idx < 0:
		return actor.global_position + Vector3(0.0, 0.9, 0.0)
	return (skeleton.global_transform * skeleton.get_bone_global_pose(idx)).origin


static func _master_yaw(actor: Node3D) -> float:
	## Prefer the posed skeleton / mesh yaw (player faces via MeshPivot, not root).
	if actor == null:
		return 0.0
	var skeleton: Skeleton3D = HeldTool.find_skeleton(actor)
	if skeleton != null:
		var forward: Vector3 = skeleton.global_transform.basis.z
		forward.y = 0.0
		if forward.length_squared() > 0.0001:
			return atan2(forward.x, forward.z)
	return actor.rotation.y
