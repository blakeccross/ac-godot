class_name IntroKkAnim
extends Node3D

## K.K. Slider host for the player-select opening (`SP_NPC_P_SEL` / `end_1`).

const ANIM_STRUM := IntroKkStage.ANIM_STRUM
const ANIM_LOOK_UP := IntroKkStage.ANIM_LOOK_UP

var _anim: AnimationPlayer
var _tree: AnimationTree
var _active: String = ""
var _face: NpcFace = NpcFace.new()


func _ready() -> void:
	global_position = IntroKkStage.gx_to_meters(IntroKkStage.KK_SPAWN_GX)
	rotation = Vector3(0.0, IntroKkStage.KK_YAW, 0.0)
	_ensure_visual()
	_setup_player()
	_bind_face()
	## Play now and again next frame — GLB AnimationPlayer finishes ready one tick later.
	play_strum()
	call_deferred("play_strum")
	call_deferred("_snap_posed_to_floor")


func body_animation_player() -> AnimationPlayer:
	return _anim


func tick_face(delta: float, uttering: bool) -> void:
	_face.tick(delta, uttering)


func play_strum() -> bool:
	return _play(ANIM_STRUM, true, IntroKkStage.STRUM_SPEED, IntroKkStage.MORPH_STRUM)


func play_look_up() -> bool:
	return _play(ANIM_LOOK_UP, true, 1.0, IntroKkStage.MORPH_LOOK_UP)


func apply_pose(pose: int) -> bool:
	match pose:
		IntroKkStage.Pose.LOOK_UP:
			return play_look_up()
		_:
			return play_strum()


func _bind_face() -> void:
	var vis: Node3D = get_node_or_null("GeneratedVisual") as Node3D
	if vis == null:
		return
	if _face.bind(vis, IntroKkStage.FACE_SPECIES):
		_face.set_emote(NpcFaceAnim.Emote.NORMAL)


func _ensure_visual() -> void:
	var vis: Node3D = get_node_or_null("GeneratedVisual") as Node3D
	if vis == null:
		return
	GeneratedVisual.apply_actor_scale(vis)
	## Rest AABB then posed snap — `4haku` sits; rest feet alone leave him floating/clipped.
	GeneratedVisual.align_actor_to_height_gx(vis, 0.0)
	GeneratedVisual.apply_preview_materials(vis)
	GeneratedVisual.stop_autoplay(vis)

func _snap_posed_to_floor() -> void:
	var vis: Node3D = get_node_or_null("GeneratedVisual") as Node3D
	if vis != null:
		GeneratedVisual.align_actor_world_min_to_height_gx(vis, 0.0)


func _setup_player() -> void:
	_anim = GeneratedVisual.find_animation_player(self)
	_tree = get_node_or_null("AnimationTree") as AnimationTree
	if _tree != null:
		_tree.active = false


func _play(suffix: String, loop: bool, speed: float, blend: float = 0.0) -> bool:
	if _anim == null:
		_setup_player()
	if _anim == null:
		return false
	var clip: String = IntroKkStage.resolve_clip(_anim, suffix)
	if clip.is_empty():
		return false
	if _tree != null:
		_tree.active = false
	if _active == clip and _anim.is_playing():
		_anim.speed_scale = speed
		return true
	var anim: Animation = _anim.get_animation(clip)
	if anim != null:
		anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	_active = clip
	_anim.speed_scale = speed
	_anim.play(clip, blend)
	return true
