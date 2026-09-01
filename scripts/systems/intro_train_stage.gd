class_name IntroTrainStage
extends RefCounted

## 3D train demo stage for Rover (`ac_npc_guide` + `rom_train_in` / door / window).
## Positions are decomp GX; converted with `FieldCatalog.GX_TO_METERS`.

signal ready_for_talk
signal assets_missing(missing: PackedStringArray)
signal stage_changed(action: StringName)

enum Action {
	ENTER,
	APPROACH,
	TALK,
	SITDOWN,
	SEATED,
	STANDUP,
	MOVE_AISLE,
	MOVE_DOOR,
	MOVE_DECK,
	KEITAI_ON,
	KEITAI_TALK,
	KEITAI_OFF,
	OPEN_DOOR,
	RETURN_APPROACH,
	LAST_SIT,
	DONE,
}

const ANIM_OPEN_D1 := "npc_1_open_d1"
const ANIM_WALK := "npc_1_walk1"
const ANIM_WAIT := "npc_1_wait1"
const ANIM_SITDOWN := "npc_1_sitdown_d1"
const ANIM_SIT_WAIT := "npc_1_sitdown_wait_d1"
const ANIM_STANDUP := "npc_1_standup_d1"
const ANIM_TO_DECK := "npc_1_to_deck_d1"
const ANIM_KEITAI_ON := "npc_1_keitai_on1"
const ANIM_KEITAI_TALK := "npc_1_keitai_talk1"
const ANIM_KEITAI_TALK2 := "npc_1_keitai_talk2"
const ANIM_KEITAI_OFF := "npc_1_keitai_off1"
const ANIM_OPEN_D2 := "npc_1_open_d2"

## `aNGD` GX landmarks.
const ROVER_START_GX := Vector3(140.0, 0.0, 130.0)
const ROVER_TALK_GX := Vector3(100.0, 0.0, 290.0)
const ROVER_SIT_GX := Vector3(100.0, 0.0, 280.0)
const ROVER_STAND_GX := Vector3(100.0, 0.0, 300.0)
const ROVER_AISLE_GX := Vector3(140.0, 0.0, 290.0)
const ROVER_DOOR_GX := Vector3(140.0, 0.0, 130.0)
const CAM_EYE_GX := Vector3(100.0, 80.0, 400.0)
const CAM_LOOK_GX := Vector3(90.0, 80.0, 280.0)
const CAM_FOV := 40.0
const WALK_SPEED_GX := 1.0 ## GX per frame @ 30 Hz → 1.5 m/s
const WALK_SPEED2_GX := 1.5
const DOOR_OPEN_FRAME := 20.0

var action: Action = Action.ENTER
var lock_camera: bool = false
var camera_morph: int = 40
var obj_look_talk: bool = false

var _rover: Node3D
var _rover_anim: AnimationPlayer
var _door: Node3D
var _door_anim: AnimationPlayer
var _keitai: Node3D
var _camera: Camera3D
var _target_gx: Vector3 = ROVER_TALK_GX
var _speed_gx: float = WALK_SPEED_GX
var _pos_gx: Vector3 = ROVER_START_GX
var _yaw: float = 0.0
var _talk_emitted: bool = false
var _door_opened: bool = false
var _clip: String = ""
var _pending_next: Action = Action.DONE
var _pending_ready: bool = false


static func gx_to_meters(gx: Vector3) -> Vector3:
	return gx * FieldCatalog.GX_TO_METERS


static func required_asset_paths() -> PackedStringArray:
	return PackedStringArray(
		[
			"res://assets/generated/environment/interiors/rom_train_in.glb",
			"res://assets/generated/environment/interiors/rom_train_out.glb",
			"res://assets/generated/environment/obj_romtrain_door.glb",
			"res://assets/generated/characters/villagers/cat_1.glb",
			"res://assets/generated/items/tol_keitai_1.glb",
		]
	)


static func missing_assets() -> PackedStringArray:
	var out := PackedStringArray()
	for path: String in required_asset_paths():
		if not ResourceLoader.exists(path):
			out.append(path)
	return out


func bind(
	rover: Node3D,
	rover_anim: AnimationPlayer,
	door: Node3D,
	door_anim: AnimationPlayer,
	keitai: Node3D,
	camera: Camera3D
) -> void:
	_rover = rover
	_rover_anim = rover_anim
	_door = door
	_door_anim = door_anim
	_keitai = keitai
	_camera = camera
	_pos_gx = ROVER_START_GX
	_yaw = 0.0
	_apply_rover_pose()
	if _keitai != null:
		_keitai.visible = false
	if _camera != null:
		_camera.fov = CAM_FOV
		_camera.near = 60.0 * FieldCatalog.GX_TO_METERS
		_camera.far = 800.0 * FieldCatalog.GX_TO_METERS
	_set_action(Action.ENTER)


## Dialogue cue: Rover sits across from the player.
func cue_sit() -> void:
	if action == Action.SEATED or action == Action.SITDOWN:
		return
	_set_action(Action.SITDOWN)


## Dialogue cue: phone call to Nook — standup, aisle, deck, keitai.
func cue_phone() -> void:
	_set_action(Action.STANDUP)


## Dialogue cue: after phone — open door and walk back if not already returning.
func cue_return_sit() -> void:
	match action:
		Action.KEITAI_TALK:
			_set_action(Action.KEITAI_OFF)
		Action.KEITAI_OFF, Action.OPEN_DOOR, Action.RETURN_APPROACH, Action.LAST_SIT, Action.SEATED:
			pass
		_:
			_set_action(Action.OPEN_DOOR)


func _set_action(next: Action) -> void:
	action = next
	stage_changed.emit(_action_name(next))
	match next:
		Action.ENTER:
			_speed_gx = WALK_SPEED_GX
			_play_rover(ANIM_OPEN_D1, false)
			_open_door()
		Action.APPROACH:
			_speed_gx = WALK_SPEED_GX
			_target_gx = ROVER_TALK_GX
			_play_rover(ANIM_WALK, true)
		Action.TALK:
			_play_rover(ANIM_WAIT, true)
			obj_look_talk = true
			camera_morph = 40
			lock_camera = false
			if not _talk_emitted:
				_talk_emitted = true
				ready_for_talk.emit()
		Action.SITDOWN:
			_pos_gx = ROVER_SIT_GX
			_yaw = 0.0
			_apply_rover_pose()
			_play_rover(ANIM_SITDOWN, false)
			_await_then(Action.SEATED)
		Action.SEATED:
			_play_rover(ANIM_SIT_WAIT, true)
		Action.STANDUP:
			obj_look_talk = false
			lock_camera = false
			_play_rover(ANIM_STANDUP, false)
			_await_then(Action.MOVE_AISLE)
		Action.MOVE_AISLE:
			_pos_gx = ROVER_STAND_GX
			_apply_rover_pose()
			_speed_gx = WALK_SPEED2_GX
			_target_gx = ROVER_AISLE_GX
			_play_rover(ANIM_WALK, true)
		Action.MOVE_DOOR:
			_speed_gx = WALK_SPEED2_GX
			_target_gx = ROVER_DOOR_GX
			_play_rover(ANIM_WALK, true)
		Action.MOVE_DECK:
			_pos_gx = ROVER_DOOR_GX
			_apply_rover_pose()
			_open_door()
			_play_rover(ANIM_TO_DECK, false)
			_await_then(Action.KEITAI_ON)
		Action.KEITAI_ON:
			if _keitai != null:
				_keitai.visible = true
			_play_rover(ANIM_KEITAI_ON, false)
			_await_then(Action.KEITAI_TALK)
		Action.KEITAI_TALK:
			_play_rover(ANIM_KEITAI_TALK, true)
		Action.KEITAI_OFF:
			_play_rover(ANIM_KEITAI_OFF, false)
			_await_then(Action.OPEN_DOOR)
		Action.OPEN_DOOR:
			if _keitai != null:
				_keitai.visible = false
			_open_door()
			_play_rover(ANIM_OPEN_D2, false)
			_await_then(Action.RETURN_APPROACH)
		Action.RETURN_APPROACH:
			_speed_gx = WALK_SPEED2_GX
			_target_gx = ROVER_TALK_GX
			_pos_gx = Vector3(140.0, 0.0, 140.0)
			_yaw = 0.0
			_apply_rover_pose()
			_play_rover(ANIM_WALK, true)
			obj_look_talk = true
			camera_morph = 40
			lock_camera = false
		Action.LAST_SIT:
			_pos_gx = ROVER_SIT_GX
			_yaw = 0.0
			_apply_rover_pose()
			_play_rover(ANIM_SITDOWN, false)
			_await_then(Action.SEATED)
		_:
			pass


func end_phone_talk() -> void:
	## Called when phone dialogue pages finish.
	if action == Action.KEITAI_TALK:
		_set_action(Action.KEITAI_OFF)


func _tick_enter(_delta: float) -> void:
	## Frame 20 of OPEN_D1 also pulses the door (decomp). Then approach.
	if not _door_opened and _rover_anim != null and _rover_anim.current_animation_position >= (DOOR_OPEN_FRAME / 30.0):
		_open_door()
	if not _anim_playing():
		_set_action(Action.APPROACH)


func _tick_move(delta: float, target: Vector3, arrive: Action) -> void:
	_target_gx = target
	var to: Vector3 = target - _pos_gx
	to.y = 0.0
	var dist: float = to.length()
	var step: float = _speed_gx * 30.0 * delta
	if dist <= step or dist < 0.5:
		_pos_gx = target
		_apply_rover_pose()
		_set_action(arrive)
		return
	var dir: Vector3 = to / dist
	_pos_gx += dir * step
	_yaw = atan2(dir.x, dir.z)
	_apply_rover_pose()


func _apply_rover_pose() -> void:
	if _rover == null:
		return
	_rover.global_position = gx_to_meters(_pos_gx)
	_rover.rotation.y = _yaw


func _open_door() -> void:
	_door_opened = true
	if _door_anim == null:
		return
	var clips: PackedStringArray = _door_anim.get_animation_list()
	if clips.is_empty():
		return
	var clip: String = clips[0]
	for name: String in clips:
		if "romtrain_door" in name or name.ends_with("door"):
			clip = name
			break
	_door_anim.play(clip)
	_door_anim.speed_scale = 0.5


func _play_rover(suffix: String, loop: bool) -> void:
	if _rover_anim == null:
		return
	var clip: String = _resolve_clip(suffix)
	if clip.is_empty():
		return
	_clip = clip
	var anim: Animation = _rover_anim.get_animation(clip)
	if anim != null:
		anim.loop_mode = (
			Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
		)
	_rover_anim.play(clip, 0.12)


func _resolve_clip(suffix: String) -> String:
	if _rover_anim == null:
		return ""
	if _rover_anim.has_animation(suffix):
		return suffix
	for anim_name: String in _rover_anim.get_animation_list():
		if anim_name.ends_with(suffix) or suffix in anim_name:
			return anim_name
	return ""


func _anim_playing() -> bool:
	if _rover_anim == null:
		return false
	return _rover_anim.is_playing()


func _await_then(next: Action) -> void:
	_pending_next = next
	if _rover_anim != null and _anim_playing():
		if not _rover_anim.animation_finished.is_connected(_on_anim_finished):
			_rover_anim.animation_finished.connect(_on_anim_finished)
		return
	## No clip / already stopped — advance on next tick (RefCounted has no call_deferred).
	_pending_ready = true


func _flush_pending() -> void:
	if _pending_next == Action.DONE:
		_pending_ready = false
		return
	var next: Action = _pending_next
	_pending_next = Action.DONE
	_pending_ready = false
	_set_action(next)


func _on_anim_finished(_anim_name: StringName) -> void:
	_flush_pending()


func tick(delta: float) -> void:
	if _pending_ready:
		_flush_pending()
	match action:
		Action.ENTER:
			_tick_enter(delta)
		Action.APPROACH:
			_tick_move(delta, ROVER_TALK_GX, Action.TALK)
		Action.MOVE_AISLE:
			_tick_move(delta, ROVER_AISLE_GX, Action.MOVE_DOOR)
		Action.MOVE_DOOR:
			_tick_move(delta, ROVER_DOOR_GX, Action.MOVE_DECK)
		Action.RETURN_APPROACH:
			_tick_move(delta, ROVER_TALK_GX, Action.LAST_SIT)
		Action.SITDOWN, Action.STANDUP, Action.KEITAI_ON, Action.KEITAI_OFF, Action.OPEN_DOOR, Action.MOVE_DECK:
			pass
		_:
			pass
	_update_camera(delta)


func _update_camera(_delta: float) -> void:
	if _camera == null:
		return
	var eye: Vector3 = gx_to_meters(CAM_EYE_GX)
	var look: Vector3 = gx_to_meters(CAM_LOOK_GX)
	if lock_camera and _rover != null:
		look = _rover.global_position + Vector3(0.0, 30.0 * FieldCatalog.GX_TO_METERS, 0.0)
	elif obj_look_talk and camera_morph > 0:
		camera_morph -= 1
		var r: float = (40.0 - float(camera_morph)) / 40.0
		var ground: Vector3 = gx_to_meters(Vector3(_pos_gx.x, 0.0, _pos_gx.z))
		var eye_y: float = 30.0 * FieldCatalog.GX_TO_METERS
		var target := Vector3(ground.x, ground.y + eye_y, ground.z)
		var start := gx_to_meters(CAM_LOOK_GX)
		look = start.lerp(target, clampf(r, 0.0, 1.0))
		if camera_morph <= 0:
			lock_camera = true
	_camera.global_position = eye
	_camera.look_at(look, Vector3.UP)


func _action_name(act: Action) -> StringName:
	match act:
		Action.ENTER:
			return &"enter"
		Action.APPROACH:
			return &"approach"
		Action.TALK:
			return &"talk"
		Action.SITDOWN:
			return &"sitdown"
		Action.SEATED:
			return &"seated"
		Action.STANDUP:
			return &"standup"
		Action.MOVE_AISLE:
			return &"move_aisle"
		Action.MOVE_DOOR:
			return &"move_door"
		Action.MOVE_DECK:
			return &"move_deck"
		Action.KEITAI_ON:
			return &"keitai_on"
		Action.KEITAI_TALK:
			return &"keitai_talk"
		Action.KEITAI_OFF:
			return &"keitai_off"
		Action.OPEN_DOOR:
			return &"open_door"
		Action.RETURN_APPROACH:
			return &"return_approach"
		Action.LAST_SIT:
			return &"last_sit"
		_:
			return &"done"
