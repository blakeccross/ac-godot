class_name FieldTrain
extends Node3D

## The town train's actors: `ac_train0` (locomotive + the mid car it draws at its sprung
## `arg0_f`), `ac_train1` (the passenger car) and `ac_npc_engineer` riding in the cab at
## `(−40, 47, 20)` GX from the loco (`aTR0_ctrl_engineer`). `TrainService` spawns it while the
## locomotive is near the player (`mTRC_trainSet`) and ticks it with `TrainControl`.

const GROUP := &"field_train"
const ENGINEER_SKELETON := &"mnk_1"
const ENGINEER_CLIP := "npc_1_wait1"
## `aNEG_actor_ct`: `world.angle.y = 0x4000` — facing +X, down the line.
const ENGINEER_YAW := PI * 0.5
const ENGINEER_OFF := Vector3(-40.0, 47.0, 20.0) * FieldCatalog.GX_TO_METERS
const WHEEL_CLIP := "obj_train1_1"
const DOOR_CLIPS: Array[String] = ["obj_train1_3_open", "obj_train1_3_close"]
## `aTR1_chg_station_attr` / `aID_ride_off_player_init` / `aSTM_intro_demo_wait_init`: the
## platform unit at the passenger-car door (2180, 820 GX, a field position). Its
## `mCoBG_ATTRIBUTE_32` walls the track edge; `STONE` opens it while a train stands there.
const STATION_GATE := Vector3(2180.0, 0.0, 820.0) * FieldCatalog.GX_TO_METERS
const ATTR_STONE := 7
const ATTR_PLATFORM_EDGE := 32
## `aTR0_set_effect` stack offset; `aTR0_steam_work` frames / x / angle per side and the
## (y, z) the steam leaves at.
const SMOKE_OFF := Vector3(36.0, 110.0, 0.0) * FieldCatalog.GX_TO_METERS
const STEAM_FRAMES: Array[Vector2i] = [Vector2i(2, 5), Vector2i(13, 16)]
const STEAM_X: Array[float] = [15.0 * FieldCatalog.GX_TO_METERS, 22.0 * FieldCatalog.GX_TO_METERS]
const STEAM_YZ := Vector2(21.0, 42.0) * FieldCatalog.GX_TO_METERS
const STEAM_ANGLE: Array[int] = [-12288, 0x0400] ## 0xD000, 0x0400

var cars: TrainCars = TrainCars.new()

var _built: bool = false
var _spawned: bool = false
var _rail_y: float = 0.0
var _loco_anim: AnimationPlayer
var _caboose_anim: AnimationPlayer
## Seconds to the next puff (`train0->arg1`) and `keyframe_saved_keyframe` (`aTR0_set_effect` /
## `aTR0_animation`).
var _smoke_wait: float = 0.0
var _saved_frame: int = -1

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
	var rail: Vector3 = TownSpace.field_to_world(Vector3(control.x, 0.0, TrainControl.RAIL_Z))
	_rail_y = _ground_y(rail)
	cars.spawn(control.x)
	_spawned = true
	visible = true
	_apply_door(TrainCars.door_setup(TrainControl.Action.WAIT_STOPPED, true))


## The passenger car's actor point (`TRAIN1` `world.position`, rail height included).
func caboose_world() -> Vector3:
	return _caboose.global_position


## `aTR0_delcheck`.
func despawn() -> void:
	if not _spawned:
		return
	_spawned = false
	visible = false


## `delta` seconds of `aTR0_actor_move` / `aTR1_actor_move`. Returns the door change, whose
## `sound` flag the caller plays.
func advance(delta: float, control: TrainControl, parked_demo: bool) -> Dictionary:
	var door: Dictionary = cars.advance(delta, control.x, control.speed, control.action, parked_demo)
	_place(_loco, control.x)
	_place(_mid, cars.mid_x)
	_place(_caboose, cars.caboose_x)
	_engineer.global_position = _loco.global_position + ENGINEER_OFF
	if _loco_anim != null:
		_loco_anim.speed_scale = IntroStationStage.loco_wheel_speed_scale(control.frame_speed()) * DecompTime.TICKS_PER_FRAME
	var frame_changed: bool = _wheel_frame_changed()
	if not is_zero_approx(control.speed) and not Game.title_demo_active:
		_smoke(delta, control.frame_speed())
		if frame_changed:
			_steam()
	if not door.is_empty():
		_apply_door(door)
		## `aTR1_chg_station_attr` (not during the first intro, which drives the gate itself).
		if not Game.intro.active:
			if cars.door_action == TrainControl.Action.WAIT_STOPPED:
				set_station_gate(get_tree(), true)
			elif cars.door_action == TrainControl.Action.SIGNAL_STARTING:
				set_station_gate(get_tree(), false)
	return door


## `aTR0_animation`: the wheel clip's cKF frame (1-based) changed since last call.
func _wheel_frame_changed() -> bool:
	if _loco_anim == null or not _loco_anim.is_playing():
		return false
	var frame: int = 1 + int(_loco_anim.current_animation_position * DecompTime.FRAME_HZ)
	if frame == _saved_frame:
		return false
	_saved_frame = frame
	return true


## `aTR0_set_effect`: a smoke puff from the stack (+36, +110), then a wait of `12 / speed`
## ticks (12 below speed 1, `speed` in GX per 1/30 s) before the next. Not in the title demos.
func _smoke(delta: float, speed: float) -> void:
	_smoke_wait -= delta
	if _smoke_wait > 0.0:
		return
	var wait_ticks: int = int(12.0 / speed) if speed >= 1.0 else 12
	_smoke_wait = maxf(_smoke_wait, 0.0) + float(wait_ticks + 1) / DecompTime.TICK_HZ
	FieldEffects.spawn(_effects(), FieldEffects.Kind.KISHA_KEMURI, _loco.global_position + SMOKE_OFF, 0.0)


## `aTR0_steam_work`: piston steam on wheel frames 2–5 (x +15, angle 0xD000) and 13–16
## (x +22, angle 0x0400), at (+21, +42) from the locomotive.
func _steam() -> void:
	for i: int in 2:
		if _saved_frame >= STEAM_FRAMES[i].x and _saved_frame <= STEAM_FRAMES[i].y:
			var at: Vector3 = _loco.global_position + Vector3(STEAM_X[i], STEAM_YZ.x, STEAM_YZ.y)
			FieldEffects.spawn(_effects(), FieldEffects.Kind.STEAM, at, float(STEAM_ANGLE[i]) * MathUtil.S16)


func _effects() -> Node:
	var world := World.find(get_tree())
	if world == null:
		return get_parent()
	var effects: Node = world.get_node_or_null("Effects")
	return effects if effects != null else world


## `mCoBG_SetAttribute(doorway, STONE | 0x20)`.
static func set_station_gate(tree: SceneTree, open: bool) -> void:
	var world := World.find(tree)
	if world == null or world.grid == null or world.layout == null:
		return
	var cell: Vector2i = world.grid.world_to_cell(TownSpace.field_to_world(STATION_GATE))
	FieldCollision.set_attr_override(world.layout, cell, ATTR_STONE if open else ATTR_PLATFORM_EDGE)


func _place(car: Node3D, x: float) -> void:
	var world: Vector3 = TownSpace.field_to_world(Vector3(x, 0.0, TrainControl.RAIL_Z))
	car.global_position = Vector3(world.x, _rail_y, world.z)


func _apply_door(door: Dictionary) -> void:
	apply_door(_caboose_anim, door)


## `aTR1_setupAction`'s `cKF_SkeletonInfo_R_init` on the passenger car's door clips.
static func apply_door(anim: AnimationPlayer, door: Dictionary) -> void:
	if anim == null:
		return
	var clip: String = _resolve(anim, DOOR_CLIPS[int(door["clip"])])
	if clip.is_empty():
		return
	var animation: Animation = anim.get_animation(clip)
	animation.loop_mode = Animation.LOOP_NONE
	anim.speed_scale = 1.0
	anim.play(clip)
	anim.seek(animation.length if bool(door["at_end"]) else 0.0, true)
	anim.speed_scale = float(door["speed"]) * DecompTime.TICKS_PER_FRAME


func _build() -> void:
	if _built:
		return
	_built = true
	GeneratedVisual.attach(_loco, &"obj_train1_1")
	GeneratedVisual.attach(_mid, &"obj_train1_2")
	GeneratedVisual.attach(_caboose, &"obj_train1_3")
	VisualTrain.center_train_visual(_loco, IntroStationStage.LOCO_MESH_CENTER)
	VisualTrain.center_train_visual(_mid, IntroStationStage.MID_MESH_CENTER)
	VisualTrain.center_train_visual(_caboose, IntroStationStage.CABOOSE_MESH_CENTER)
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
