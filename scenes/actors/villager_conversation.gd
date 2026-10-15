class_name VillagerConversation
extends Node

## A villager in conversation: holding still and facing the speaker, the face and mouth
## following the line (`NpcFace`), reaction clips cued by a line's manpu code
## (`aNPC_check_manpu_demoCode`), the first-job lines, and letting go when the talk closes.
## A child of the `Villager`; it reads the villager's body animation and state directly.

var _face_mood: int = -1

## The Villager this belongs to (the parent), found on first use: tests build scenes
## without adding them to the tree.
var _villager: Villager:
	get:
		if _villager == null:
			_villager = get_parent() as Villager
		return _villager


func try_first_job_talk(ctx: InteractionContext) -> bool:
	if Game == null or Game.first_job == null or not Game.first_job.is_active():
		return false
	if _villager.data == null or _villager.data.id == &"":
		return false
	var job: FirstJob = Game.first_job
	var who: String = _villager.data.display_name if _villager.data else "Villager"
	var player: Node3D = ctx.actor as Node3D if ctx != null else null
	if job.can_deliver_to(_villager.data.id, Game.inventory):
		var delivered_id: StringName = job.item_id
		if player != null:
			await HandOver.player_gives_to_npc(player, _villager, delivered_id)
		if not job.try_deliver_to(_villager.data.id, Game.inventory):
			return false
		if Game.relationships != null:
			Game.relationships.record_gift(
				_villager.data.id,
				delivered_id if delivered_id != &"" else &"delivery",
				VillagerTalk.day_key()
			)
		_play_first_job_line(&"nook_job_deliver_ok", who, player)
		Game.set_interact_prompt("Talk to Tom Nook")
		if _villager.state != null:
			_villager.state.record_talk(VillagerTalk.day_key())
		return true
	## The "ask around for work" chore finishes in the quest talk ("Need any help?",
	## `aQMgr_talk_quest_finish_firstjob_open_quest`).
	return false


func note_first_job_talk() -> void:
	if Game == null or Game.first_job == null or _villager.data == null:
		return
	Game.first_job.note_villager_talked(_villager.data.id)
	if Game.first_job.kind == FirstJob.Kind.INTRODUCTIONS and Game.first_job.chore_finished():
		Game.set_interact_prompt("Talk to Tom Nook")


func _play_first_job_line(conv_id: StringName, who: String, player: Node3D) -> void:
	var talk_data: DialogueData = DialogueCatalog.conversation(conv_id)
	var talk_ctx: DialogueContext = DialogueContext.from_game(_villager.data, _villager.state)
	talk_ctx.speaker_name = who
	var ui := DialogueOverlay.find(get_tree())
	if ui != null and talk_data != null:
		if ui.is_open():
			ui.close()
		_villager.ai.begin_talk()
		bind_talk_end(ui)
		if player != null:
			TalkCamera.begin(player, _villager, get_tree())
		sing_town_tune(talk_ctx)
		ui.play(talk_data, talk_ctx, _villager.state)
	else:
		Game.post_notice("%s: Thanks!" % who)


func hold_talk(delta: float) -> void:
	var on_bg: bool = _villager._snap_to_bg()
	if on_bg:
		_villager.velocity.y = 0.0
		_villager.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	elif not _villager.is_on_floor():
		_villager.velocity.y -= _villager._gravity * delta
	else:
		_villager.velocity.y = 0.0
	_villager.velocity.x = 0.0
	_villager.velocity.z = 0.0
	_refresh_talk_look()
	_villager._motor.turn_toward(delta, _villager.global_position, _villager._talk_look)
	if _villager._model != null:
		_villager._model.rotation.y = _villager._motor.facing
	if _villager._agent != null and _villager.mover.nav_ready():
		_villager._agent.target_position = _villager.global_position
	_villager.move_and_slide()
	if on_bg:
		_villager._snap_to_bg()
	_villager._update_animation(delta, Vector3.ZERO)
	_villager.ai.step(delta)


func tick_face(delta: float) -> void:
	sync_face_mood(false)
	_villager._face.tick(delta, _dialogue_uttering())


func sync_face_mood(force: bool) -> void:
	_villager._ensure_bound()
	var mood: int = int(_villager.state.mood) if _villager.state != null else int(VillagerState.Mood.NORMAL)
	if not force and mood == _face_mood:
		return
	_face_mood = mood
	_villager._face.set_from_mood(mood)


func _dialogue_uttering() -> bool:
	if not _villager.ai.is_talking() or get_tree() == null:
		return false
	return DialogueOverlay.uttering_in(get_tree())


## `mMld_ActorMakeMelody` as a talk starts: the town tune in this villager's voice.
func sing_town_tune(talk_ctx: DialogueContext) -> void:
	if Game != null and talk_ctx != null:
		Audio.play_melody(Game.town_tune, DialogueVoice.melody_voice(talk_ctx.sound_spec))


func bind_talk_end(ui: DialogueOverlay) -> void:
	if ui == null:
		return
	if ui.closed.is_connected(_on_talk_closed):
		ui.closed.disconnect(_on_talk_closed)
	ui.closed.connect(_on_talk_closed, CONNECT_ONE_SHOT)
	if not ui.event_fired.is_connected(_on_talk_event):
		ui.event_fired.connect(_on_talk_event)


func unbind_talk() -> void:
	if get_tree() != null:
		var ui := DialogueOverlay.find(get_tree())
		if ui != null and ui.closed.is_connected(_on_talk_closed):
			ui.closed.disconnect(_on_talk_closed)
		if ui != null and ui.event_fired.is_connected(_on_talk_event):
			ui.event_fired.disconnect(_on_talk_event)
	_end_manpu()
	if _villager.ai.is_talking():
		TalkCamera.end(get_tree())
		_villager.ai.end_talk()


## The quest talk wants the pockets opened or an item passed across
## (`aQMgr_TALK_SUB_STATE_HAND_ITEM_WAIT`, `aQMgr_talk_common_set_npc_takeout_*`).
func on_talk_action(action: Dictionary, ui: DialogueOverlay, player: Node3D) -> void:
	await TalkActions.handle(action, ui, _villager, player)


func _on_talk_event(event: Dictionary) -> void:
	if not _villager.ai.is_talking() or str(event.get("op", "")) != "manpu":
		return
	cue_manpu(str(event.get("name", event.get("code", ""))))


## `aNPC_check_manpu_demoCode`: a talk line's reaction clip, its face and its feel glyph.
func cue_manpu(key: String) -> void:
	if NpcManpu.is_reset(key):
		_end_manpu()
		_villager._play_clip(Villager.ANIM_WAIT, true)
		return
	_villager._face.set_emote(NpcManpu.emote_for(key), NpcManpu.mouth_hold_for(key))
	var clip: String = NpcManpu.clip_for(key)
	if _villager._resolve_clip(clip).is_empty():
		return
	if _villager._feel != null and not _villager._manpu_clip.is_empty():
		_villager._feel.release()
	_villager._play_clip(clip, false)
	_villager._manpu_clip = _villager._clip
	_villager._manpu_follow = ""
	if _villager._feel != null:
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			var to_cam: Vector3 = cam.global_position - _villager.global_position
			_villager._feel.faces_camera = Vector3(sin(_villager._motor.facing), 0.0, cos(_villager._motor.facing)).dot(to_cam) >= 0.0
		_villager._feel.npc_yaw = _villager._motor.facing
		_villager._feel.play_for_manpu(key)


func _end_manpu() -> void:
	_villager._manpu_clip = ""
	_villager._manpu_follow = ""
	if _villager._feel != null:
		_villager._feel.release()
	sync_face_mood(true)


func _on_talk_closed() -> void:
	if _villager._fortune_calling:
		_villager._fortune_calling = false
		_villager._fortune_cool = VillagerFortune.CALL_COOLDOWN_SEC
	TalkCamera.end(get_tree())
	_villager.ai.end_talk()
	if get_tree() != null:
		var ui := DialogueOverlay.find(get_tree())
		if ui != null and ui.event_fired.is_connected(_on_talk_event):
			ui.event_fired.disconnect(_on_talk_event)
	_end_manpu()
	## `aNPC_think_pitfall_main_proc`: a talk in the pit ends with `aNPC_ACT_REVIVE`.
	if _villager._pit == Villager.Pit.STRUGGLE:
		_villager._begin_revive()
	## `Common_Set(npc_chg_cloth, …)`: a shirt handed over in the talk goes on.
	if _villager.state != null and _villager._cloth_key() != _villager._drawn_cloth:
		_villager._apply_design_wear()
		_villager._drawn_cloth = _villager._cloth_key()
	if Game != null and Game.first_job != null and Game.first_job.kind == FirstJob.Kind.OPEN and Game.first_job.chore_finished():
		Game.set_interact_prompt("Talk to Tom Nook")
	## `mNpc_TalkEndMove` (from `aQMgr_move_talk` when the talk demo ends).
	if _villager._talk_manager != null and Game != null and _villager.data != null:
		Game.npc_talk_info.talk_end(_villager._talk_manager.slot, _villager._talk_manager.looks)
	_villager._talk_manager = null


func _refresh_talk_look() -> void:
	if get_tree() == null:
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	if player is Node3D:
		_villager._talk_look = (player as Node3D).global_position
