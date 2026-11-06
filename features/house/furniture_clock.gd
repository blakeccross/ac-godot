class_name FurnitureClock
extends Node

## The clocks among the furniture (`ac_kon_*clock`, `ac_sum_*clk*`, `ac_nog_tri_clock01`,
## `ac_yos_turkey_watch`, …). Any piece with a `*_short_model` and a `*_long_model` joint is one: its
## hands turn to the time (`joint->z -= rad_hour / rad_min`, the same `HouseClock.hand_angles`).
## The pendulum clocks tick (`SE 0x12D`) twice every 120 game frames — frames 15 and 45 of the room's
## clock (`aMR_MakeClockInfo`) — and start their swing over at frame 0, so they all beat together.
## The pigeon clock pops out on the hour, once for each hour (12 at midnight and noon), and once on the
## half hour (`aSumLogHatoclk_mv`, `SE 0x133` two frames into each pop).

## Pieces that tick: visual id → the SE (`sAdo_OngenTrgStart(0x12D, …)`).
const TICKS := {
	&"int_sum_oldclk01": &"12d",
	&"int_sum_blue_clk": &"12d",
	&"int_sum_x_clk": &"12d",
	&"int_kon_atqclock": &"12d",
}
const PIGEON := &"int_sum_log_hatoclk"
const PIGEON_SE := &"133"
## `pappo_count_table`: pops on the hour, by hour of the day.
const PIGEON_HOURS: Array[int] = [12, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
## `play->game_frame % 120`.
const PERIOD_FRAMES := 120
const TICK_FRAMES: Array[int] = [15, 45]
## A pop runs at `speed 1.0` a game frame: twice the clip's own 30 fps.
const POP_SPEED := 2.0
## `GETREG(MYKREG, 33) + 2.0`: the clip frame the sound comes on.
const POP_SE_FRAME := 2.0

var _visual_id: StringName = &""
var _piece: Node3D
var _skeleton: Skeleton3D
var _anim: AnimationPlayer
var _hour_bone: int = -1
var _min_bone: int = -1
var _hour_rest := Quaternion.IDENTITY
var _min_rest := Quaternion.IDENTITY
var _stamp: int = -1
var _frame: int = -1
var _pops_left: int = 0
var _popping: bool = false
var _last_second: int = -1


## A clock for `piece` drawn from `visual`, or null when it has no hands.
static func attach(piece: Node3D, visual: Node, visual_id: StringName) -> FurnitureClock:
	if piece == null or visual == null:
		return null
	var skeleton: Skeleton3D = _find_skeleton(visual)
	if skeleton == null:
		return null
	var hour: int = -1
	var minute: int = -1
	for i: int in skeleton.get_bone_count():
		var bone: String = skeleton.get_bone_name(i)
		if bone.ends_with("_short_model"):
			hour = i
		elif bone.ends_with("_long_model"):
			minute = i
	if hour < 0 and minute < 0:
		return null
	var clock := FurnitureClock.new()
	clock.name = "FurnitureClock"
	clock._visual_id = visual_id
	clock._piece = piece
	clock._skeleton = skeleton
	clock._anim = VisualAnimation.find_animation_player(visual)
	clock._hour_bone = hour
	clock._min_bone = minute
	if hour >= 0:
		clock._hour_rest = skeleton.get_bone_rest(hour).basis.get_rotation_quaternion()
	if minute >= 0:
		clock._min_rest = skeleton.get_bone_rest(minute).basis.get_rotation_quaternion()
	## After the clip has written its pose each frame.
	clock.process_priority = 100
	piece.add_child(clock)
	clock._turn_hands()
	if visual_id == PIGEON and clock._anim != null:
		clock._anim.stop()
	return clock


## Pops owed at `hour`:`minute` (`aSumLogHatoclk_mv`): the hour's count on the hour, one on the half hour.
static func pops_at(hour: int, minute: int) -> int:
	if minute == 0:
		return PIGEON_HOURS[posmod(hour, 24)]
	if minute == 30:
		return 1
	return 0


func _process(_delta: float) -> void:
	if _piece == null or not is_instance_valid(_piece):
		return
	var stamp: int = Clock.hour * 60 + Clock.minute
	if stamp != _stamp:
		_turn_hands()
	_turn_hands_pose()
	if TICKS.has(_visual_id):
		_pendulum()
	elif _visual_id == PIGEON:
		_pigeon()


func _turn_hands() -> void:
	_stamp = Clock.hour * 60 + Clock.minute
	_turn_hands_pose()


func _turn_hands_pose() -> void:
	if _skeleton == null:
		return
	var a: Vector2 = HouseClock.hand_angles(Clock.hour, Clock.minute)
	if _hour_bone >= 0:
		_skeleton.set_bone_pose_rotation(_hour_bone, _hour_rest * Quaternion(Vector3.BACK, -a.x))
	if _min_bone >= 0:
		_skeleton.set_bone_pose_rotation(_min_bone, _min_rest * Quaternion(Vector3.BACK, -a.y))


func _pendulum() -> void:
	var frame: int = Engine.get_physics_frames() % PERIOD_FRAMES
	if frame == _frame:
		return
	_frame = frame
	if frame == 0 and _anim != null and not _anim.get_animation_list().is_empty():
		_anim.speed_scale = 0.5
		_anim.play(_anim.get_animation_list()[0])
	if TICK_FRAMES.has(frame):
		Audio.play_se(TICKS[_visual_id] as StringName, _piece)


func _pigeon() -> void:
	if _anim == null:
		return
	var second: int = Clock.hour * 3600 + Clock.minute * 60 + Clock.second
	if second != _last_second:
		_last_second = second
		if _pops_left <= 0 and not _popping and Clock.second == 0:
			_pops_left = pops_at(Clock.hour, Clock.minute)
	if _pops_left > 0 and not _popping:
		_pop()


func _pop() -> void:
	var clips: PackedStringArray = _anim.get_animation_list()
	if clips.is_empty():
		_pops_left = 0
		return
	_popping = true
	_anim.speed_scale = POP_SPEED
	_anim.play(clips[0])
	get_tree().create_timer(POP_SE_FRAME / 30.0 / POP_SPEED).timeout.connect(
		func() -> void:
			if is_instance_valid(_piece):
				Audio.play_se(PIGEON_SE, _piece)
	)
	await _anim.animation_finished
	_anim.seek(0.0, true)
	_anim.stop()
	_pops_left -= 1
	_popping = false


static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child: Node in node.get_children():
		var s: Skeleton3D = _find_skeleton(child)
		if s != null:
			return s
	return null
