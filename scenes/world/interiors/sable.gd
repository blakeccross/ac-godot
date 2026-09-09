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
var _story_ids: Array[int] = []
var _story_index: int = 0
var _active_ui: Node = null
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
		var ui: Node = get_tree().get_first_node_in_group("dialogue_ui")
		if ui != null and ui.has_method("is_uttering"):
			uttering = bool(ui.call("is_uttering"))
	_face.tick(delta, uttering)


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	return [Interaction.of(Interaction.TALK, "Talk to Sable", 20)]


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.TALK or Game == null:
		return false
	return _begin_talk(ctx)


func _begin_talk(ctx: InteractionContext) -> bool:
	var listener: Node3D = ctx.actor as Node3D if ctx != null else null
	_face_toward(listener.global_position if listener != null else global_position)
	if Game.designs != null:
		var was_first := Game.designs.sable_last_date != _today()
		Game.designs.tick_sable_day(_today())
		_story_ids = _pick_story(was_first)
	else:
		_story_ids = []
	_story_index = 0
	## Slow the sewing loop while talking (decomp anim speed 0.5).
	if _body_anim != null:
		_body_anim.speed_scale = 0.5
	_start_talk_session(listener)
	_advance_story()
	_talked_today = true
	return true


func _pick_story(was_first: bool) -> Array[int]:
	if Game == null or Game.designs == null:
		return []
	## sable_days has already been ticked, so pass first_of_day = false and the
	## current (post-tick) count.
	var row := NeedleworkTalk.pick_story_row(Game.designs.sable_days, false, _rng)
	if Game.designs.sable_days == 0:
		row = 0
	return NeedleworkTalk.story_line_ids(row, _rng)


func _advance_story() -> void:
	var ui: Node = get_tree().get_first_node_in_group("dialogue_ui") if get_tree() != null else null
	if ui == null:
		_end_talk()
		return
	if _story_index >= _story_ids.size():
		if _story_ids.is_empty() and ui.has_method("say"):
			_bind_end(ui)
			ui.call("say", "...", "Sable")
			return
		_end_talk()
		return
	var data: DialogueData = NeedleworkTalk.line(_story_ids[_story_index])
	_story_index += 1
	if data == null:
		_advance_story()
		return
	var ctx := _make_ctx()
	if ui.has_method("play"):
		_bind_next(ui)
		ui.call("play", data, ctx)
	elif ui.has_method("say"):
		_bind_end(ui)
		ui.call("say", "...", "Sable")


func _make_ctx() -> DialogueContext:
	var c: DialogueContext = DialogueContext.from_game()
	c.speaker_name = "Sable"
	c.speaker_sex = 1
	c.voice_mode = DialogueVoice.Mode.ANIMALESE
	c.sound_spec = 4
	c.frees = PackedStringArray(["Mabel", "Sable"])
	c.already_talked = _talked_today
	return c


func _bind_next(ui: Node) -> void:
	_active_ui = ui
	if ui.has_signal("closed"):
		if ui.is_connected("closed", _on_line_closed):
			ui.disconnect("closed", _on_line_closed)
		ui.connect("closed", _on_line_closed, CONNECT_ONE_SHOT)


func _bind_end(ui: Node) -> void:
	if ui == null or not ui.has_signal("closed") or ui.is_connected("closed", _on_talk_closed):
		return
	ui.connect("closed", _on_talk_closed, CONNECT_ONE_SHOT)


func _on_line_closed() -> void:
	if _story_index < _story_ids.size():
		_advance_story()
	else:
		_end_talk()


func _on_talk_closed() -> void:
	_end_talk()


func _end_talk() -> void:
	_talking = false
	_active_ui = null
	if _body_anim != null:
		_body_anim.speed_scale = 1.0
	TalkCamera.end(get_tree())
	_face_machine()  ## back to the sewing machine


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
	_body_anim = GeneratedVisual.find_animation_player(vis)
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
