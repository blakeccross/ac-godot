extends StaticBody3D

## Outdoor Tortimer at the wishing well (`SP_NPC_SONCHO` / `fd_npc_land` ut 10,10 on
## `mRF_BLOCKKIND_SHRINE`). Present while the first job is active (`mFM_SetMoveActor`).

const ANIM_WAIT := "npc_1_wait1"
const GREETING_ID := &"tortimer_greeting"

var _model: Node3D
var _body_anim: AnimationPlayer
var _face: NpcFace = NpcFace.new()
var _talking: bool = false


func _ready() -> void:
	add_to_group("interactable")
	_ensure_visual()
	_refresh_presence()
	if Game != null and Game.first_job != null and Game.first_job.has_signal("changed"):
		if not Game.first_job.changed.is_connected(_refresh_presence):
			Game.first_job.changed.connect(_refresh_presence)


func _exit_tree() -> void:
	if Game != null and Game.first_job != null and Game.first_job.changed.is_connected(_refresh_presence):
		Game.first_job.changed.disconnect(_refresh_presence)


func _process(delta: float) -> void:
	if not visible:
		return
	var uttering: bool = false
	if _talking and get_tree() != null:
		uttering = DialogueOverlay.uttering_in(get_tree())
	_face.advance(delta, uttering)
	if _talking:
		_face_player()


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	if not visible:
		return []
	return [Interaction.of(Interaction.TALK, "Talk to Tortimer", 20)]


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if not visible:
		return false
	if action == null or action.id != Interaction.TALK or Game == null:
		return false
	var listener: Node3D = ctx.actor as Node3D if ctx != null else null
	if Game.first_job != null:
		Game.first_job.mark_met_tortimer()
		if Game.first_job.kind == FirstJob.Kind.INTRODUCTIONS and Game.first_job.chore_finished():
			Game.set_interact_prompt("Talk to Tom Nook")
	return _begin_talk(listener)


func _refresh_presence() -> void:
	## `mFM_SetMoveActor`: spawn only while `mEv_CheckFirstJob`.
	var show: bool = Game != null and Game.first_job != null and Game.first_job.is_active()
	visible = show
	collision_layer = 1 if show else 0
	var volume: Node = get_node_or_null("InteractVolume")
	if volume is CollisionObject3D:
		(volume as CollisionObject3D).collision_layer = 8 if show else 0


func _begin_talk(listener: Node3D) -> bool:
	var data: DialogueData = DialogueCatalog.conversation(GREETING_ID)
	var talk_ctx: DialogueContext = DialogueContext.from_game()
	talk_ctx.speaker_name = "Tortimer"
	var ui := DialogueOverlay.find(get_tree())
	if ui != null and data != null:
		if ui.is_open():
			ui.close()
		_talking = true
		if listener != null:
			TalkCamera.begin(listener, self, get_tree())
		if not ui.closed.is_connected(_on_talk_closed):
			ui.closed.connect(_on_talk_closed, CONNECT_ONE_SHOT)
		ui.play(data, talk_ctx)
	else:
		Game.post_notice("Tortimer: Ho ho! Welcome!")
	return true


func _on_talk_closed() -> void:
	_talking = false
	TalkCamera.end(get_tree())


func _face_player() -> void:
	var player := Player.find(get_tree())
	if player is Node3D:
		var to: Vector3 = (player as Node3D).global_position - global_position
		to.y = 0.0
		if to.length_squared() > 0.0001:
			rotation.y = atan2(to.x, to.z)


func _ensure_visual() -> void:
	if _model != null:
		return
	_model = $Model
	var vis: Node3D = GeneratedVisual.attach_villager(_model, &"ttl")
	if vis == null:
		vis = GeneratedVisual.attach_villager(_model, &"rcn")
	if vis == null:
		return
	_body_anim = VisualAnimation.find_animation_player(vis)
	_face.bind(vis, &"ttl")
	## Imported `npc_1_wait1` is a one-shot. Without a loop he sways once, then freezes.
	if _body_anim != null and _body_anim.has_animation(ANIM_WAIT):
		var animation: Animation = _body_anim.get_animation(ANIM_WAIT)
		if animation != null:
			animation.loop_mode = Animation.LOOP_LINEAR
		_body_anim.play(ANIM_WAIT)
