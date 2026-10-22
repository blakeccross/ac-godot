class_name BodyAnimator
extends AnimationTree

## A character's body animation: an `AnimationTree` over the generated model's clips.
##
## The tree (`body_animation.tres`, shared by the player and villagers) is a `Body`
## state machine feeding a `Speed` time scale:
## - `Move` is a synced transition over the walk / run / dash gait clips. Switching gait
##   keeps the step phase (`frame = current_frame` in `Player_actor_CulcAnimation_*`);
##   entering it from anything else starts the gait at frame 1.
## - `ClipA` / `ClipB` each play one named clip through a `TimeSeek`. A new clip goes to
##   whichever is idle, so it crossfades out of the one playing (`morph` frames).
##
## The model's `AnimationPlayer` only holds the libraries (the tree reads them, so
## `get_animation` / `has_animation` work as on the player); it never plays. The methods
## mirror the `AnimationPlayer` calls callers already make (`play`, `seek`,
## `is_playing`, `current_animation`, `animation_finished`), so one-shot actions read
## the same as before.

const MOVE := &"Move"
const CLIP_STATES: Array[StringName] = [&"ClipA", &"ClipB"]
const SPEED := &"parameters/Speed/scale"
const GAIT := &"parameters/Body/Move/Gait/transition_request"
const PLAYBACK := &"parameters/Body/playback"
## The method the clip-event tracks call on this node.
const EVENT_METHOD := &"_on_clip_event"

## A frame marked with `add_clip_events` came up in `clip`. Not while a clip plays
## backwards: a mark is where the action happens going forwards.
signal clip_event(clip: StringName, event: StringName)

## Gait clip per `Move` input; written into this body's copy of the tree.
@export var gait_clips: Dictionary = {&"walk": "ply_1_walk1", &"run": "ply_1_run1", &"dash": "ply_1_dash1"}

## Playback rate, like `AnimationPlayer.speed_scale`. Negative plays backwards.
var speed_scale: float = 1.0:
	set(value):
		speed_scale = value
		if tree_root != null:
			set(SPEED, value)

## The clip playing (a gait clip while moving), as `AnimationPlayer.current_animation`.
var current_animation: String:
	get:
		return _clip

## Seconds into the current clip, as `AnimationPlayer.current_animation_position`.
var current_animation_position: float:
	get:
		return _position()

var _player: AnimationPlayer
var _clip: String = ""
var _state: StringName = &""
var _gait: StringName = &""
var _playing: bool = false
## Position to report until the tree has processed a fresh start or seek.
var _pending: float = -1.0


func _ready() -> void:
	## Each body changes clip names and fade times on its own copy.
	if tree_root != null:
		tree_root = tree_root.duplicate(true)
		var move: AnimationNodeBlendTree = _body().get_node(MOVE)
		for gait: StringName in gait_clips:
			var node := StringName(String(gait).capitalize())
			if move.has_node(node):
				(move.get_node(node) as AnimationNodeAnimation).animation = gait_clips[gait]
	active = false
	mixer_applied.connect(_check_finished)


## Drive the clips of `player` (the model's `AnimationPlayer`, which then stays idle).
func bind(player: AnimationPlayer) -> void:
	_player = player
	if player == null:
		active = false
		return
	player.stop()
	VisualAnimation.clear_autoplay(player)
	player.active = false
	anim_player = get_path_to(player)
	root_node = get_path_to(player.get_node(player.root_node))
	active = true
	set(SPEED, speed_scale)


func is_bound() -> bool:
	return _player != null and is_instance_valid(_player)


## `AnimationPlayer.play`: start `clip`, fading over `blend` seconds (0 cuts). Calling it
## again for the clip already playing changes nothing, as with `AnimationPlayer`.
func play(clip: StringName, blend: float = 0.0) -> void:
	if not is_bound() or not _player.has_animation(clip):
		return
	if String(clip) == _clip and _playing and _state != MOVE:
		return
	_start_clip(clip, blend, 0.0)


## `AnimationPlayer.play_backwards`: from the clip's end towards its start.
func play_backwards(clip: StringName, blend: float = 0.0) -> void:
	var anim: Animation = get_animation(clip)
	if anim == null:
		return
	speed_scale = -absf(speed_scale if speed_scale != 0.0 else 1.0)
	_start_clip(clip, blend, anim.length)


## Walk, run or dash at `rate` (the gait's `speed_scale`). From another gait the step
## phase carries over; from a clip the gait starts at its first frame after `blend`.
func play_gait(gait: StringName, rate: float, blend: float) -> void:
	if not is_bound() or not gait_clips.has(gait):
		return
	speed_scale = rate
	set(GAIT, String(gait))
	_gait = gait
	_clip = gait_clips[gait]
	_playing = true
	if _state == MOVE:
		return
	_travel(MOVE, blend)
	_pending = 0.0


## `AnimationPlayer.seek`: jump the current clip to `seconds`. `update` applies the pose
## now instead of on the next process.
func seek(seconds: float, update: bool = false) -> void:
	if not is_bound() or _state == &"" or _state == MOVE:
		return
	set(&"parameters/Body/%s/Seek/seek_request" % _state, seconds)
	_pending = seconds
	_playing = true
	if update:
		advance(0.0)


## Write `marks` ({clip: [[frame, event], …]}, frames at `fps`) into the clips as
## method-call tracks on this node, replacing any this body wrote before. The events then
## fire on the clip's own clock: late if it is slowed, never if it is cut off or sought past.
func add_clip_events(marks: Dictionary, fps: float) -> void:
	if not is_bound():
		return
	var path: NodePath = get_node(root_node).get_path_to(self)
	_own_clips()
	for clip: Variant in marks:
		var anim: Animation = _player.get_animation(StringName(clip))
		if anim == null:
			continue
		var track: int = _event_track(anim)
		if track < 0:
			track = anim.add_track(Animation.TYPE_METHOD)
		anim.track_set_path(track, path)
		while anim.track_get_key_count(track) > 0:
			anim.track_remove_key(track, 0)
		for mark: Array in marks[clip]:
			var at: float = clampf(float(mark[0]) / fps, 0.0, anim.length)
			anim.track_insert_key(track, at, {"method": EVENT_METHOD, "args": [StringName(clip), mark[1]]})


## The model's clips are shared with every other instance of the same glb (the inventory
## portrait, the title demo). Method tracks pointing at this node would not resolve there, so
## edit a private copy of the library.
func _own_clips() -> void:
	for library_name: StringName in _player.get_animation_library_list():
		var library: AnimationLibrary = _player.get_animation_library(library_name)
		var copy := AnimationLibrary.new()
		for clip_name: StringName in library.get_animation_list():
			copy.add_animation(clip_name, library.get_animation(clip_name).duplicate())
		_player.remove_animation_library(library_name)
		_player.add_animation_library(library_name, copy)
	## The tree copies the player's libraries when it is pointed at it.
	var player_path: NodePath = anim_player
	anim_player = NodePath()
	anim_player = player_path


func is_playing() -> bool:
	return is_bound() and _playing


func stop() -> void:
	_playing = false


func _start_clip(clip: StringName, blend: float, at: float) -> void:
	var target: StringName = CLIP_STATES[1] if _state == CLIP_STATES[0] else CLIP_STATES[0]
	var node: AnimationNodeBlendTree = _body().get_node(target)
	(node.get_node(&"Clip") as AnimationNodeAnimation).animation = clip
	_clip = String(clip)
	_gait = &""
	_playing = true
	_travel(target, blend)
	set(&"parameters/Body/%s/Seek/seek_request" % target, at)
	_pending = at


func _travel(target: StringName, blend: float) -> void:
	var body: AnimationNodeStateMachine = _body()
	var playback: AnimationNodeStateMachinePlayback = get(PLAYBACK)
	for i: int in body.get_transition_count():
		if body.get_transition_from(i) == _state and body.get_transition_to(i) == target:
			body.get_transition(i).xfade_time = maxf(blend, 0.0)
	if _state == &"" or blend <= 0.0:
		playback.start(target, true)
	else:
		playback.travel(target, true)
	_state = target


func _on_clip_event(clip: StringName, event: StringName) -> void:
	if speed_scale >= 0.0:
		clip_event.emit(clip, event)


static func _event_track(anim: Animation) -> int:
	for i: int in anim.get_track_count():
		if anim.track_get_type(i) != Animation.TYPE_METHOD:
			continue
		for k: int in anim.track_get_key_count(i):
			if anim.method_track_get_name(i, k) == EVENT_METHOD:
				return i
	return -1


func _body() -> AnimationNodeStateMachine:
	return (tree_root as AnimationNodeBlendTree).get_node(&"Body") as AnimationNodeStateMachine


func _position() -> float:
	if not is_bound():
		return 0.0
	if _pending >= 0.0:
		return _pending
	var playback: AnimationNodeStateMachinePlayback = get(PLAYBACK)
	return playback.get_current_play_position()


## A one-shot clip that has run out stops, and says so, as `AnimationPlayer` does.
func _check_finished() -> void:
	_pending = -1.0
	if not _playing or _state == MOVE or _state == &"":
		return
	var anim: Animation = get_animation(_clip)
	if anim == null or anim.loop_mode != Animation.LOOP_NONE or speed_scale == 0.0:
		return
	var playback: AnimationNodeStateMachinePlayback = get(PLAYBACK)
	if playback.get_current_node() != _state:
		return
	var pos: float = playback.get_current_play_position()
	var ended: bool = pos <= 0.0001 if speed_scale < 0.0 else pos >= anim.length - 0.0001
	if ended:
		_playing = false
		animation_finished.emit(StringName(_clip))
