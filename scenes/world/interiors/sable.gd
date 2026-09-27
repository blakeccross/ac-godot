extends StaticBody3D

## Sable — the quiet sister at the sewing machine (`ac_npc_needlework` /
## `SP_NPC_NEEDLEWORK1`, skeleton `hgs_1`). She sits pinned at the machine, and
## only opens up over the 10-day `nw_visitor` friendship arc
## (`ac_npc_needlework_talk.c_inc`).

const SPECIES := &"hgs"
## `aNPC_ANIM_MISIN1` (`cKF_ba_r_npc_1_misin1`) — she works the machine on repeat.
const ANIM_SEW := "npc_1_misin1"
const ANIM_FALLBACK := "npc_1_wait1"

## Decomp: Sable sits behind the machine facing SOUTH toward the player / the work
## (`head.lock_flag`, rotation {0,0,0}). NPC mesh forward = +Z at yaw 0.
@export var face_yaw: float = 0.0

var _model: Node3D
var _body_anim: AnimationPlayer
var _face: NpcFace = NpcFace.new()
var _talking: bool = false
var _talked_today: bool = false
var _clip: String = ""
## Current sister story (`sister_story`) and the message ids for its parts.
var _story_row: int = 0
var _story_ids: Array[int] = []
var _story_index: int = 0
## `nw_visitor.days >= 5` — she looks up from the machine for this talk.
var _turns_to_player: bool = false
var _active_ui: DialogueOverlay = null
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("needlework_set")
	add_to_group("needlework_sable")
	collision_layer = 1
	collision_mask = 0
	_rng.randomize()
	_ensure_collision()
	_ensure_visual()
	_ensure_interact()


func _face_machine() -> void:
	rotation.y = face_yaw


func _process(delta: float) -> void:
	var uttering: bool = false
	if _talking and get_tree() != null:
		uttering = DialogueOverlay.uttering_in(get_tree())
	_face.tick(delta, uttering)


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	return [Interaction.of(Interaction.TALK, "Talk to Sable", 20)]


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.TALK or Game == null:
		return false
	return _begin_talk(ctx)


## `aNNW_set_norm_talk_info` (talk_idx 2 → `aNNW_set_ane_msg`) then `aNNW_talk_init`:
## the story row is picked from the day counter *before* today's visit is counted
## (`aNNW_get_make_sister_message` adds it itself), then `aNNW_day_day` bumps it.
func _begin_talk(ctx: InteractionContext) -> bool:
	var listener: Node3D = ctx.actor as Node3D if ctx != null else null
	_story_row = 0
	_story_ids = []
	if Game.designs != null:
		var first := Game.designs.sable_last_date != _today()
		_story_row = NeedleworkTalk.pick_story_row(Game.designs.sable_days, first, _rng)
		_story_ids = NeedleworkTalk.story_line_ids(_story_row, _rng)
		Game.designs.tick_sable_day(_today())
		_turns_to_player = Game.designs.sable_days >= NeedleworkTalk.SABLE_TURN_DAYS
	else:
		_turns_to_player = false
	_story_index = 0
	if _turns_to_player and listener != null:
		_face_toward(listener.global_position)
	## The machine and the fabric stop; her own loop slows to half speed.
	NeedleworkPresenter.set_machine_running(get_parent(), false)
	if _body_anim != null:
		_body_anim.speed_scale = 0.5
	_start_talk_session(listener)
	_advance_story()
	_talked_today = true
	return true


## One part of the story: Sable (`ANE_0`), Mabel turned to face her (`AINOTE` → force
## talk 5), Sable again (`AINOTE3` → force talk 6; story 9 turns her to the player,
## `aNNW_talk_ane_3`).
func _advance_story() -> void:
	var ui := DialogueOverlay.find(get_tree())
	if ui == null or _story_index >= maxi(_story_ids.size(), 1):
		_end_talk()
		return
	var now := _story_index
	var msg: int = _story_ids[now] if now < _story_ids.size() else -1
	_story_index += 1
	var speaker := NeedleworkTalk.story_speaker(now)
	var mabel: Node3D = _mabel()
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if speaker == "Mabel" and mabel != null:
		if mabel.has_method("chime_in"):
			mabel.call("chime_in", self)
		TalkCamera.begin(mabel, self, get_tree(), false)
	else:
		if mabel != null and mabel.has_method("chime_in"):
			mabel.call("chime_in", self if now > 0 else null)
		if now == 2 and _story_row == NeedleworkTalk.STORY_TURN_TO_PLAYER and player != null:
			_face_toward(player.global_position)
		if player != null:
			TalkCamera.begin(player, self, get_tree(), false)
	var text := NeedleworkTalk.story_text(_story_row, now, msg)
	_bind_next(ui)
	ui.play(DialogueData.from_dict({"id": "sable_story", "start": "l",
		"nodes": {"l": {"type": "line", "text": text}}}), _make_ctx(speaker))


func _make_ctx(speaker: String = "Sable") -> DialogueContext:
	var c: DialogueContext = DialogueContext.from_game()
	c.speaker_name = speaker
	## Special NPC — default green nameplate, like Mabel / Tom Nook.
	c.voice_mode = DialogueVoice.Mode.ANIMALESE
	c.sound_spec = 4
	c.frees = PackedStringArray(["Mabel", "Sable"])
	c.already_talked = _talked_today
	return c


func _bind_next(ui: DialogueOverlay) -> void:
	_active_ui = ui
	if ui.closed.is_connected(_on_line_closed):
		ui.closed.disconnect(_on_line_closed)
	ui.closed.connect(_on_line_closed, CONNECT_ONE_SHOT)


func _on_line_closed() -> void:
	if _story_index < _story_ids.size():
		_advance_story()
	else:
		_end_talk()


func _end_talk() -> void:
	_talking = false
	_active_ui = null
	if _body_anim != null:
		_body_anim.speed_scale = 1.0
	var mabel: Node3D = _mabel()
	if mabel != null and mabel.has_method("chime_in"):
		mabel.call("chime_in", null)
	TalkCamera.end(get_tree())
	## `aNNW_THINK_TURN` → back to the machine (`MISIN_WAIT`), which starts up again.
	_face_machine()
	NeedleworkPresenter.set_machine_running(get_parent(), true)


func _mabel() -> Node3D:
	return get_tree().get_first_node_in_group("needlework_mabel") as Node3D if get_tree() != null else null


func _start_talk_session(listener: Node3D) -> void:
	_talking = true
	if listener != null:
		TalkCamera.begin(listener, self, get_tree())


func _face_toward(target: Vector3) -> void:
	var to: Vector3 = target - global_position
	to.y = 0.0
	if to.length_squared() > 0.0001:
		rotation.y = atan2(to.x, to.z)


func _today() -> String:
	return "%04d-%02d-%02d" % [Clock.year, Clock.month, Clock.day]


func _ensure_collision() -> void:
	if get_node_or_null("CollisionShape3D") != null:
		return
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.6, 1.0)
	shape.shape = box
	shape.position = Vector3(0.0, 0.8, 0.0)
	add_child(shape)


func _ensure_interact() -> void:
	if get_node_or_null("InteractVolume") != null:
		return
	var volume := Area3D.new()
	volume.name = "InteractVolume"
	volume.collision_layer = 8
	volume.collision_mask = 0
	volume.monitoring = false
	volume.monitorable = true
	volume.set_script(load("res://scenes/world/interact_volume.gd"))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.0, 2.0)
	shape.shape = box
	shape.position = Vector3(0.0, 1.0, 0.0)
	volume.add_child(shape)
	add_child(volume)


func _ensure_visual() -> void:
	if get_node_or_null("Model") != null:
		return
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	var vis: Node3D = GeneratedVisual.attach_villager(_model, SPECIES)
	if vis == null:
		var mesh := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.3
		capsule.height = 1.1
		mesh.mesh = capsule
		mesh.position.y = 0.7
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.5, 0.42, 0.5)
		mesh.material_override = mat
		_model.add_child(mesh)
		return
	_body_anim = VisualAnimation.find_animation_player(vis)
	_face.bind(vis, SPECIES)
	rotation.y = face_yaw
	_play_clip(ANIM_SEW if _body_anim != null and _body_anim.has_animation(ANIM_SEW) else ANIM_FALLBACK, true)


func _play_clip(suffix: String, loop: bool) -> void:
	if _body_anim == null:
		return
	var clip := _resolve_clip(suffix)
	if clip.is_empty() or (clip == _clip and _body_anim.is_playing()):
		return
	_clip = clip
	var animation: Animation = _body_anim.get_animation(clip)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	_body_anim.play(clip, 0.12)


func _resolve_clip(suffix: String) -> String:
	if _body_anim == null or suffix.is_empty():
		return ""
	if _body_anim.has_animation(suffix):
		return suffix
	for anim_name: String in _body_anim.get_animation_list():
		if anim_name.ends_with(suffix) or suffix in anim_name:
			return anim_name
	return ""
