class_name FieldTrain
extends Node3D

## The town train's actors: `ac_train0` (locomotive + the mid car it draws at its sprung
## `arg0_f`), `ac_train1` (the passenger car) and `ac_npc_engineer` riding in the cab at
## `(−40, 47, 20)` from the loco (`aTR0_ctrl_engineer`). `TrainService` spawns it while the
## locomotive is near the player (`mTRC_trainSet`) and ticks it with `TrainControl`.

const GROUP := &"field_train"
const ENGINEER_SKELETON := &"mnk_1"
const ENGINEER_CLIP := "npc_1_wait1"
## `aNEG_actor_ct`: `world.angle.y = 0x4000` — facing +X, down the line.
const ENGINEER_YAW := PI * 0.5
const ENGINEER_OFF_GX := Vector3(-40.0, 47.0, 20.0)
const WHEEL_CLIP := "obj_train1_1"
const DOOR_CLIPS: Array[String] = ["obj_train1_3_open", "obj_train1_3_close"]

var cars: TrainCars = TrainCars.new()

var _built: bool = false
var _spawned: bool = false
var _rail_y: float = 0.0
var _loco_anim: AnimationPlayer
var _caboose_anim: AnimationPlayer

@onready var _loco: Node3D = %Loco
@onready var _mid: Node3D = %Mid
@onready var _caboose: Node3D = %Caboose
@onready var _engineer: Node3D = %Engineer


func _ready() -> void:
	add_to_group(GROUP)
	visible = false


func is_spawned() -> bool:
	return _spawned


## `mTRC_trainSet`: create the actors at the locomotive's rail point; the height is sampled
## once (`mCoBG_GetBgY_OnlyCenter_FromWpos2`) and kept.
func spawn(control: TrainControl) -> void:
	_build()
	var rail: Vector3 = TownSpace.gx_to_world(Vector3(control.x_gx, 0.0, TrainControl.RAIL_Z_GX))
	_rail_y = _ground_y(rail)
	cars.spawn(control.x_gx)
	_spawned = true
	visible = true
	_apply_door(TrainCars.door_setup(TrainControl.Action.WAIT_STOPPED, true))


## `aTR0_delcheck`.
func despawn() -> void:
	if not _spawned:
		return
	_spawned = false
	visible = false


## One actor tick (`aTR0_actor_move` / `aTR1_actor_move`). Returns the door change, whose
## `sound` flag the caller plays.
func tick(control: TrainControl, parked_demo: bool) -> Dictionary:
	var door: Dictionary = cars.step(control.x_gx, control.speed, control.action, parked_demo)
	_place(_loco, control.x_gx)
	_place(_mid, cars.mid_x)
	_place(_caboose, cars.caboose_x)
	_engineer.global_position = _loco.global_position + ENGINEER_OFF_GX * FieldCatalog.GX_TO_METERS
	if _loco_anim != null:
		_loco_anim.speed_scale = IntroStationStage.loco_wheel_speed_scale(control.speed) * DecompTime.TICKS_PER_FRAME
	if not door.is_empty():
		_apply_door(door)
	return door


func _place(car: Node3D, x_gx: float) -> void:
	var world: Vector3 = TownSpace.gx_to_world(Vector3(x_gx, 0.0, TrainControl.RAIL_Z_GX))
	car.global_position = Vector3(world.x, _rail_y, world.z)


func _apply_door(door: Dictionary) -> void:
	if _caboose_anim == null:
		return
	var clip: String = _resolve(_caboose_anim, DOOR_CLIPS[int(door["clip"])])
	if clip.is_empty():
		return
	var animation: Animation = _caboose_anim.get_animation(clip)
	animation.loop_mode = Animation.LOOP_NONE
	_caboose_anim.speed_scale = 1.0
	_caboose_anim.play(clip)
	_caboose_anim.seek(animation.length if bool(door["at_end"]) else 0.0, true)
	_caboose_anim.speed_scale = float(door["speed"]) * DecompTime.TICKS_PER_FRAME


func _build() -> void:
	if _built:
		return
	_built = true
	GeneratedVisual.attach(_loco, &"obj_train1_1")
	GeneratedVisual.attach(_mid, &"obj_train1_2")
	GeneratedVisual.attach(_caboose, &"obj_train1_3")
	VisualTrain.center_train_visual(_loco, IntroStationStage.LOCO_MESH_CENTER_GX)
	VisualTrain.center_train_visual(_mid, IntroStationStage.MID_MESH_CENTER_GX)
	VisualTrain.center_train_visual(_caboose, IntroStationStage.CABOOSE_MESH_CENTER_GX)
	GeneratedVisual.attach_special_npc(_engineer, ENGINEER_SKELETON)
	_engineer.rotation.y = ENGINEER_YAW
	_play_loop(VisualAnimation.find_animation_player(_engineer), ENGINEER_CLIP)
	_loco_anim = VisualAnimation.find_animation_player(_loco)
	_play_loop(_loco_anim, WHEEL_CLIP)
	_caboose_anim = VisualAnimation.find_animation_player(_caboose)


func _ground_y(world: Vector3) -> float:
	var host: Node = get_parent()
	var layout: WorldData = host.get("layout") as WorldData if host != null else null
	var grid: WorldGrid = host.get("grid") as WorldGrid if host != null else null
	if layout == null or grid == null:
		return world.y
	var y: float = FieldCollision.ground_y_at(layout, grid, world, 0.0, false)
	return y if FieldCollision.has_floor(y) else world.y


func _play_loop(anim: AnimationPlayer, clip: String) -> void:
	var resolved: String = _resolve(anim, clip)
	if resolved.is_empty():
		return
	var animation: Animation = anim.get_animation(resolved)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR
	anim.play(resolved)


static func _resolve(anim: AnimationPlayer, clip: String) -> String:
	if anim == null:
		return ""
	for anim_name: String in anim.get_animation_list():
		if anim_name == clip or anim_name.ends_with(clip):
			return anim_name
	return ""
