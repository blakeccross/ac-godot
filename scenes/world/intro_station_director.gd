extends Node

## Runs `IntroStationStage` inside a generated `WorldScene` (title **Station Arrival**).

## Prefer imported bank ids (`0x07DD`…); authored JSON is the no-bank fallback.
const PORTER_DIALOGUE := &"msg_2013"
const PORTER_DIALOGUE_FALLBACK := &"porter_arrive"
const NOOK_CALL_DIALOGUE := &"msg_2014"
const NOOK_CALL_DIALOGUE_FALLBACK := &"nook_station_call"
const NOOK_INTRO_DIALOGUE := &"msg_2015"
const NOOK_INTRO_DIALOGUE_FALLBACK := &"nook_station_greeting"
const NOOK_HOUSES_DIALOGUE := &"msg_2017"
const NOOK_HOUSES_DIALOGUE_FALLBACK := &"nook_show_houses"
const NOOK_HOUSE_LOOK_DIALOGUE := &"msg_2020"
const NOOK_HOUSE_LOOK_DIALOGUE_FALLBACK := &"nook_house_look"
const NOOK_DEBT_DIALOGUE := &"msg_2022"
const NOOK_DEBT_DIALOGUE_FALLBACK := &"nook_house_debt"
const NOOK_JOB_DIALOGUE := &"nook_first_job"

var _world: Node3D
var _stage: IntroStationStage = IntroStationStage.new()
var _player: CharacterBody3D
var _camera: Camera3D
var _dialogue: CanvasLayer
var _loco: Node3D
var _mid: Node3D
var _caboose: Node3D
var _engineer: Node3D
var _porter: Node3D
var _nook: Node3D
var _actors: Node3D
var _finishing: bool = false
var _resume_debt: bool = false
var _last_dialogue_id: StringName = &""
var _pending_look_house_id: StringName = &""
var _entering_look_house: bool = false
var _nook_face: NpcFace = NpcFace.new()
var _nook_feel: NpcFeelGlyphs
var _nook_manpu_hold: String = ""


func setup(world: Node3D) -> void:
	_world = world
	name = "IntroStationDirector"
	_resume_debt = Game.intro_station_resume_debt
	call_deferred("_boot")


func _boot() -> void:
	if _world == null or not is_instance_valid(_world):
		queue_free()
		return
	_player = _world.get_node_or_null("Characters/Player") as CharacterBody3D
	_camera = _world.get_node_or_null("FollowCamera") as Camera3D
	var hud: Node = _world.get_node_or_null("ClockHud")
	if hud != null:
		_dialogue = hud.get_node_or_null("DialogueOverlay") as CanvasLayer
	if _player == null or _camera == null:
		push_warning("IntroStationDirector: missing player or camera")
		Game.complete_intro_station()
		queue_free()
		return
	var station: Node3D = _world.get_node_or_null("Buildings/station") as Node3D
	if station == null:
		push_warning("IntroStationDirector: no station building in generated town")
		Game.complete_intro_station()
		queue_free()
		return

	_actors = Node3D.new()
	_actors.name = "IntroStationActors"
	_world.add_child(_actors)
	if not _resume_debt:
		_loco = _spawn_structure(&"obj_train1_1", "TrainLoco")
		_mid = _spawn_structure(&"obj_train1_2", "TrainMid")
		_caboose = _spawn_structure(&"obj_train1_3", "TrainCaboose")
		_engineer = _spawn_villager(&"mnk_1", "Engineer")
		_porter = _spawn_villager(&"mnk_1", "Porter")
	_nook = _spawn_villager(&"rcn_1", "Nook")
	if _nook != null:
		_nook.visible = false

	var origin: Vector3 = _station_block_origin(station)
	var houses_gx: Array[Vector3] = _collect_house_gx(origin)
	var explain: Vector3 = _explain_gx_for_houses(origin, houses_gx)
	var nook_spawn: Vector3 = IntroStationStage.NOOK_SPAWN_GX
	var out_z: float = IntroStationStage.OUT_STATION_Z_GX
	## Leave the station acre southward relative to the platform doorway.
	out_z = maxf(out_z, IntroStationStage.DOORWAY_GX.z + 120.0)

	_stage.drive_player = false
	_stage.drive_camera = true
	_stage.set_block_origin(origin)
	_stage.set_world_ground(_world.layout as WorldData, _world.grid as WorldGrid)
	_stage.bind(_loco, _mid, _caboose, _engineer, _porter, _nook, _player, _camera)
	## Landmarks after bind — bind used to reset house GX to the station-lawn stub.
	_stage.set_landmarks(out_z, nook_spawn, IntroStationStage.NOOK_FACE_GX, explain, houses_gx)
	_stage.porter_talk_requested.connect(_on_porter_talk)
	_stage.nook_call_requested.connect(_on_nook_call)
	_stage.nook_introduce_requested.connect(_on_nook_introduce)
	_stage.nook_show_houses_requested.connect(_on_nook_show_houses)
	_stage.nook_debt_requested.connect(_on_nook_debt)
	_stage.nook_job_requested.connect(_on_nook_job)
	_stage.house_pick_enabled.connect(_on_house_pick_enabled)
	_stage.stage_changed.connect(_on_stage_changed)
	_stage.finished.connect(_on_finished)
	if _dialogue != null and _dialogue.has_signal("closed"):
		if not _dialogue.closed.is_connected(_on_dialogue_closed):
			_dialogue.closed.connect(_on_dialogue_closed)
	if _dialogue != null and _dialogue.has_signal("event_fired"):
		if not _dialogue.event_fired.is_connected(_on_dialogue_event):
			_dialogue.event_fired.connect(_on_dialogue_event)
	if not Game.intro_house_look_requested.is_connected(_on_intro_house_look):
		Game.intro_house_look_requested.connect(_on_intro_house_look)

	## Fresh arrival only — do not restart train/arrive BGM after leaving a house.
	if not _resume_debt:
		var bgm: StringName = IntroStationStage.BGM_ID
		if BgmCatalog.stream_for(bgm) == null:
			bgm = &"intro_train"
		Audio.play_bgm(bgm)

	if _resume_debt:
		Game.intro_station_resume_debt = false
		_stage.drive_camera = false
		_resume_follow_camera(true)
		## `aID_birth_rcn_guide` on outdoor return: Nook is already at the door
		## while the player GO_OUT / emerges (`aNRG_restart_wait`).
		_place_nook_at_claimed_house()
		call_deferred("_resume_debt_sequence")
	else:
		if _camera.has_method("suspend"):
			_camera.call("suspend")
		_player.set_busy(true)
		if _player.has_method("set_cutscene_driven"):
			_player.call("set_cutscene_driven", true)
		_stage.reset()


func _resume_debt_sequence() -> void:
	## World defers `play_emerge` before this director boots — give it a head start.
	if get_tree() != null:
		await get_tree().process_frame
		await get_tree().process_frame
	if _player != null and _player.has_method("is_door_entering"):
		while is_instance_valid(_player) and bool(_player.call("is_door_entering")):
			await get_tree().process_frame
	if _finishing or _player == null or not is_instance_valid(_player):
		return
	## Face + wait after emerge, then force-talk (`aNRG_restart_wait` → RESTART_TALK).
	_face_nook_toward_player()
	_nook_play_wait()
	_player.set_busy(true)
	if _player.has_method("set_cutscene_driven"):
		_player.call("set_cutscene_driven", false)
	if _player.has_method("play_wait_idle"):
		_player.call("play_wait_idle")
	## `0x07E6` → CAMERA2_PROCESS_TALK + turn.
	_begin_demo_talk(_nook, true, true)
	_stage.begin_debt_after_house()


func _process(delta: float) -> void:
	if _finishing or _stage == null:
		return
	_stage.tick(delta)
	## Keep the real player locked while the stage owns pose / cutscenes.
	if _player != null and is_instance_valid(_player):
		_player.set_busy(_stage.player_controls_locked())
		if _player.has_method("set_cutscene_driven"):
			_player.call("set_cutscene_driven", _stage.player_cutscene_driven())
	_tick_nook_talk(delta)


func _tick_nook_talk(delta: float) -> void:
	var uttering: bool = false
	if _dialogue != null and _dialogue.has_method("is_uttering"):
		uttering = bool(_dialogue.call("is_uttering"))
	_nook_face.tick(delta, uttering)
	if _nook_manpu_hold.is_empty():
		return
	var anim: AnimationPlayer = GeneratedVisual.find_animation_player(_nook)
	if anim == null or anim.is_playing():
		return
	var hold := _nook_manpu_hold
	_nook_manpu_hold = ""
	_nook_play_clip(hold, true)


func _unhandled_input(event: InputEvent) -> void:
	if _finishing:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause_menu"):
		get_viewport().set_input_as_handled()
		Game.abort_intro_sequence()


func _spawn_structure(visual_id: StringName, node_name: String) -> Node3D:
	var host := Node3D.new()
	host.name = node_name
	_actors.add_child(host)
	GeneratedVisual.attach(host, visual_id)
	## `attach` already calls `prepare_outdoor_train` for `obj_train1_*`.
	return host


func _spawn_villager(skel_id: StringName, node_name: String) -> Node3D:
	## `mesh_paths` only resolves `obj_*`; special NPCs use villager GLB prefixes (`mnk_1`, `rcn_1`).
	var host := Node3D.new()
	host.name = node_name
	_actors.add_child(host)
	var path: String = "res://assets/generated/characters/villagers/%s.glb" % String(skel_id)
	if not ResourceLoader.exists(path):
		push_warning("IntroStationDirector: missing %s" % path)
		return host
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return host
	var pivot := Node3D.new()
	pivot.name = "GeneratedVisual"
	pivot.add_child(packed.instantiate())
	host.add_child(pivot)
	GeneratedVisual.apply_actor_scale(pivot, skel_id)
	GeneratedVisual.align_actor_to_height_gx(pivot, 0.0)
	GeneratedVisual.apply_preview_materials(pivot)
	GeneratedVisual.stop_autoplay(pivot)
	if skel_id == &"rcn_1":
		_nook_face.bind(pivot, &"rcn")
		_ensure_nook_feel(host)
	return host


func _ensure_nook_feel(host: Node3D) -> void:
	if host == null:
		return
	if _nook_feel != null and is_instance_valid(_nook_feel):
		return
	_nook_feel = NpcFeelGlyphs.new()
	_nook_feel.name = "FeelGlyphs"
	host.add_child(_nook_feel)
	## Head is roughly 1.6 m on the scaled rcn mesh.
	_nook_feel.set_head_lift(1.55)


func _station_block_origin(station: Node3D) -> Vector3:
	## Acre NW corner in world meters — demo GX is relative to that block.
	var layout: WorldData = _world.layout as WorldData
	var grid: WorldGrid = _world.grid as WorldGrid
	if layout != null and grid != null:
		for b: BuildingPlacement in layout.buildings:
			if b == null or b.id != &"station":
				continue
			var acre_nw := Vector2i(
				int(floor(float(b.cell.x) / 16.0)) * 16,
				int(floor(float(b.cell.y) / 16.0)) * 16
			)
			return grid.cell_corner(acre_nw)
	## Fallback: reverse from the placed station actor (unit 8,5 −20 X).
	var origin: Vector3 = station.global_position - IntroStationStage.gx_to_meters(
		IntroStationStage.STATION_GX
	)
	origin.y = 0.0
	return origin


func _collect_house_gx(origin: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var buildings: Node = _world.get_node_or_null("Buildings")
	if buildings == null:
		return out
	for child in buildings.get_children():
		if child == null or not String(child.name).begins_with("player_house"):
			continue
		if child is Node3D:
			var n: Node3D = child as Node3D
			out.append((n.global_position - origin) / FieldCatalog.GX_TO_METERS)
	out.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		if absf(a.z - b.z) > 1.0:
			return a.z < b.z
		return a.x < b.x
	)
	return out


func _explain_gx_for_houses(origin: Vector3, houses_gx: Array[Vector3]) -> Vector3:
	## Stand in front of the vacant doors (porch approach), not behind the roofs.
	## `aNRG` TAKE_WITH ends near the cluster; EXPLAIN faces the house fronts.
	var approaches: Array[Vector3] = []
	var buildings: Node = _world.get_node_or_null("Buildings") if _world != null else null
	if buildings != null:
		for child in buildings.get_children():
			if child == null or not String(child.name).begins_with("player_house"):
				continue
			if child is Node3D:
				var approach: Vector3 = StructureDoor.approach_position(child as Node3D)
				approaches.append((approach - origin) / FieldCatalog.GX_TO_METERS)
	if approaches.is_empty():
		if houses_gx.is_empty():
			return IntroStationStage.NOOK_EXPLAIN_GX
		## Fallback: south of the southernmost actor (doors face +Z / south).
		var sum := Vector3.ZERO
		var max_z: float = houses_gx[0].z
		for h: Vector3 in houses_gx:
			sum += h
			max_z = maxf(max_z, h.z)
		var avg: Vector3 = sum / float(houses_gx.size())
		return Vector3(avg.x, 0.0, max_z + 80.0)
	var sum_a := Vector3.ZERO
	for a: Vector3 in approaches:
		sum_a += a
	return sum_a / float(approaches.size())


func _place_nook_at_claimed_house() -> void:
	## `aID_birth_rcn_guide` restart: beside the outdoor exit stand for the loan talk.
	## Decomp ±10/+8 GX is from a *neighbor unit cell*, not the door stand — applying
	## that to `exit_stand` puts Nook on the player. Use ~1 unit (40 GX) lateral.
	if _nook == null or _world == null:
		return
	_nook.visible = true
	var house: Node3D = _claimed_house()
	var stand: Vector3 = (
		_player.global_position if _player != null else Vector3.ZERO
	)
	if house != null:
		stand = StructureDoor.exit_stand(house)
	var side := Vector3.RIGHT
	if house != null:
		var leave: float = StructureDoor.leave_yaw(house, stand)
		var forward := Vector3(sin(leave), 0.0, cos(leave))
		side = Vector3(forward.z, 0.0, -forward.x)
		if side.length_squared() < 0.0001:
			side = Vector3.RIGHT
		else:
			side = side.normalized()
		## Prefer the side that opens toward town / away from the house body.
		var away: Vector3 = stand - house.global_position
		away.y = 0.0
		if away.dot(side) < 0.0:
			side = -side
	var gx: float = FieldCatalog.GX_TO_METERS
	_nook.global_position = stand + side * (40.0 * gx)
	_nook.global_position.y = stand.y
	_face_nook_toward_player()
	_nook_play_wait()


func _claimed_house() -> Node3D:
	if _world == null:
		return null
	if Game.intro_station_house_id != &"":
		var named: Node3D = _world.get_node_or_null(
			"Buildings/%s" % String(Game.intro_station_house_id)
		) as Node3D
		if named != null:
			return named
	var buildings: Node = _world.get_node_or_null("Buildings")
	if buildings == null:
		return null
	for child in buildings.get_children():
		if child != null and String(child.name).begins_with("player_house"):
			return child as Node3D
	return null


func _face_nook_toward_player() -> void:
	if _nook == null or _player == null:
		return
	var to_player: Vector3 = _player.global_position - _nook.global_position
	to_player.y = 0.0
	if to_player.length_squared() > 0.0001:
		_nook.rotation.y = atan2(to_player.x, to_player.z)


func _nook_play_wait() -> void:
	_nook_manpu_hold = ""
	_nook_play_clip("npc_1_wait1", true)


func _nook_play_clip(clip_leaf: String, loop: bool) -> void:
	if _nook == null or clip_leaf.is_empty():
		return
	var anim: AnimationPlayer = GeneratedVisual.find_animation_player(_nook)
	if anim == null:
		return
	anim.autoplay = ""
	var resolved := _resolve_anim_clip(anim, clip_leaf)
	if resolved.is_empty() and anim.get_animation_list().size() > 0 and loop:
		resolved = _resolve_anim_clip(anim, "npc_1_wait1")
	if resolved.is_empty():
		return
	var animation: Animation = anim.get_animation(resolved)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	if anim.current_animation != resolved or not anim.is_playing():
		anim.play(resolved)


func _resolve_anim_clip(anim: AnimationPlayer, want: String) -> String:
	if anim == null or want.is_empty():
		return ""
	if anim.has_animation(want):
		return want
	for anim_name: String in anim.get_animation_list():
		if (
			anim_name == want
			or anim_name.ends_with("/" + want)
			or anim_name.ends_with(want)
		):
			return anim_name
	return ""


func _on_dialogue_event(event: Dictionary) -> void:
	var op := String(event.get("op", event.get("type", "")))
	match op:
		"manpu", "set_emote":
			_apply_nook_manpu(event)


func _apply_nook_manpu(event: Dictionary) -> void:
	var op := String(event.get("op", event.get("type", "")))
	var name := str(event.get("name", event.get("manpu", event.get("emote", ""))))
	if name.is_empty() and event.has("code"):
		name = str(event.get("code"))
	if name.is_empty():
		return
	if op == "set_emote":
		_nook_face.set_emote(_emote_from_name(name))
		return
	_nook_manpu_hold = ""
	var clip := NpcManpu.clip_for(name)
	if clip.is_empty():
		return
	_nook_face.set_emote(NpcManpu.emote_for(name), NpcManpu.mouth_hold_for(name))
	if _nook_feel == null and _nook != null:
		_ensure_nook_feel(_nook)
	if _nook_feel != null:
		_nook_feel.play_for_manpu(name)
	if NpcManpu.loops(name):
		_nook_play_clip(clip, true)
		return
	var hold := _manpu_hold_for(clip)
	if not hold.is_empty() and _nook != null:
		var anim: AnimationPlayer = GeneratedVisual.find_animation_player(_nook)
		if anim != null and not _resolve_anim_clip(anim, hold).is_empty():
			_nook_manpu_hold = hold
	_nook_play_clip(clip, false)


func _manpu_hold_for(attack_clip: String) -> String:
	if attack_clip.ends_with("_d1"):
		return attack_clip.trim_suffix("1") + "2"
	if attack_clip.ends_with("1"):
		return attack_clip.trim_suffix("1") + "2"
	return ""


func _emote_from_name(name: String) -> NpcFaceAnim.Emote:
	match name.strip_edges().to_lower():
		"laugh", "happy", "fun", "smile", "niko":
			return NpcFaceAnim.Emote.LAUGH
		"angry", "mad", "punpun", "musu", "hate":
			return NpcFaceAnim.Emote.ANGRY
		"sad", "komari", "gloomy":
			return NpcFaceAnim.Emote.SAD
		"surprise", "shock", "gaaan", "hirameki":
			return NpcFaceAnim.Emote.SURPRISE
		"cry":
			return NpcFaceAnim.Emote.CRY
		"sleepy":
			return NpcFaceAnim.Emote.SLEEPY
		_:
			return NpcManpu.emote_for(name)


func _on_stage_changed(action: StringName) -> void:
	if action == &"player_control" or action == &"player_pick":
		_stage.drive_camera = false
		_resume_follow_camera(false)
	elif action == &"nook_lead":
		## Guided walk — follow camera, stick locked (`aID_walk_after_rcn_guide`).
		_stage.drive_camera = false
		_resume_follow_camera(false)
	elif action == &"nook_call" or action == &"nook_approach":
		## Keep follow while Nook talks / runs.
		_stage.drive_camera = false
		_resume_follow_camera(false)


func _resume_follow_camera(snap: bool) -> void:
	if _camera == null:
		return
	if _camera.has_method("set_target"):
		_camera.call("set_target", _player)
	if _camera.has_method("resume"):
		## Prefer smooth handoff from DEMO doorway framing (Godot 4 named args).
		_camera.call("resume", snap)


func _on_house_pick_enabled(enabled: bool) -> void:
	Game.intro_station_can_pick_house = enabled
	if enabled:
		Game.set_interact_prompt("Choose a house")


func _on_porter_talk() -> void:
	## `0x07DD` → CAMERA2_PROCESS_NORMAL + turn (no GetAngleY).
	_begin_demo_talk(_porter, false, true)
	_play_dialogue(PORTER_DIALOGUE, "Porter", PORTER_DIALOGUE_FALLBACK)


func _on_nook_call() -> void:
	## `0x07DE` → CAMERA2_PROCESS_NORMAL + turn.
	_begin_demo_talk(_nook, false, true)
	_play_dialogue(NOOK_CALL_DIALOGUE, "Tom Nook", NOOK_CALL_DIALOGUE_FALLBACK)


func _on_nook_introduce() -> void:
	## `0x07DF` → CAMERA2_PROCESS_TALK + turn.
	_begin_demo_talk(_nook, true, true)
	_play_dialogue(NOOK_INTRO_DIALOGUE, "Tom Nook", NOOK_INTRO_DIALOGUE_FALLBACK)


func _on_nook_show_houses() -> void:
	## `0x07E1` → CAMERA2_PROCESS_TALK + turn.
	_begin_demo_talk(_nook, true, true)
	_play_dialogue(NOOK_HOUSES_DIALOGUE, "Tom Nook", NOOK_HOUSES_DIALOGUE_FALLBACK)


func _on_intro_house_look(house_id: StringName) -> void:
	## `msg_2020` / `0x07E4` before the door — NORMAL cam, turn off.
	_pending_look_house_id = house_id
	if _player != null:
		_player.set_busy(true)
	_face_nook_toward_player()
	_nook_play_wait()
	_begin_demo_talk(_nook, false, false)
	_play_dialogue(NOOK_HOUSE_LOOK_DIALOGUE, "Tom Nook", NOOK_HOUSE_LOOK_DIALOGUE_FALLBACK)


func _on_nook_debt() -> void:
	## `0x07E6` → CAMERA2_PROCESS_TALK + turn (also set in `_resume_debt_sequence`).
	_begin_demo_talk(_nook, true, true)
	_play_dialogue(NOOK_DEBT_DIALOGUE, "Tom Nook", NOOK_DEBT_DIALOGUE_FALLBACK)


func _on_nook_job() -> void:
	## Bank `msg_2022` already chains through the loan / part-time job (`msg_2028`).
	## Only play the authored job stub when the debt line was the short fallback.
	if _last_dialogue_id == NOOK_DEBT_DIALOGUE:
		_stage.notify_dialogue_closed()
		return
	_begin_demo_talk(_nook, true, true)
	_play_dialogue(NOOK_JOB_DIALOGUE, "Tom Nook")


func _play_dialogue(id: StringName, speaker: String, fallback: StringName = &"") -> void:
	if _dialogue == null or not _dialogue.has_method("play"):
		_end_demo_talk()
		_stage.notify_dialogue_closed()
		return
	var data: DialogueData = DialogueCatalog.conversation(id)
	if data == null and fallback != &"":
		data = DialogueCatalog.conversation(fallback)
		id = fallback
	if data == null:
		_end_demo_talk()
		_stage.notify_dialogue_closed()
		return
	_last_dialogue_id = id
	var ctx := DialogueContext.new()
	ctx.speaker_name = speaker
	ctx.player_name = Game.player_name
	ctx.town_name = Game.town_name
	_fill_shop_acre_frees(ctx)
	_dialogue.call("play", data, ctx)


func _begin_demo_talk(npc: Node3D, talk_camera: bool, turn: bool) -> void:
	## `aSTM` / `aNRG` force-talk `camera_type` + `turn_flag`.
	if _player == null or npc == null:
		return
	if talk_camera:
		TalkCamera.begin(_player, npc, get_tree(), turn)
		return
	TalkCamera.end(get_tree())
	if turn and _player.has_method("begin_talk_face"):
		_player.call("begin_talk_face", npc)


func _end_demo_talk() -> void:
	TalkCamera.end(get_tree())


func _fill_shop_acre_frees(ctx: DialogueContext) -> void:
	## `msg_2028` "Acre {free1}-{free2}" — Nook's shop block letter/number.
	if _world == null or _world.layout == null:
		return
	var layout: WorldData = _world.layout as WorldData
	for b: BuildingPlacement in layout.buildings:
		if b == null:
			continue
		var is_shop: bool = b.id == &"acre_shop" or b.kind == &"shop"
		if not is_shop:
			continue
		var bx: int = int(floor(float(b.cell.x) / 16.0))
		var bz: int = int(floor(float(b.cell.y) / 16.0))
		## Playable FG acres are 1..5 / 1..6; letter A–F for north→south.
		var letter := char(64 + clampi(bz, 1, 6))
		ctx.frees = PackedStringArray([letter, str(clampi(bx, 1, 5))])
		return


func _on_dialogue_closed() -> void:
	## After `msg_2020`, claim the plot and walk through the door.
	if _pending_look_house_id != &"" and not _entering_look_house:
		_end_demo_talk()
		_enter_pending_look_house()
		return
	## Rejecting a house (`msg_2023`) returns to pick instead of the job offer.
	if _stage != null and _stage.action == IntroStationStage.Action.NOOK_DEBT:
		var runner: DialogueRunner = null
		if _dialogue != null and _dialogue.has_method("runner"):
			runner = _dialogue.call("runner") as DialogueRunner
		if runner != null and runner.conversation != null:
			var end_id: StringName = runner.conversation.id
			if end_id == &"msg_2023":
				_end_demo_talk()
				Game.intro_station_house_id = &""
				Game.intro_station_resume_debt = false
				_stage.notify_house_pick_again()
				return
	_end_demo_talk()
	_stage.notify_dialogue_closed()


func _enter_pending_look_house() -> void:
	var house_id: StringName = _pending_look_house_id
	_pending_look_house_id = &""
	_entering_look_house = true
	Game.claim_intro_house(house_id)
	var house: Node3D = null
	if _world != null:
		house = _world.get_node_or_null("Buildings/%s" % String(house_id)) as Node3D
	if house != null:
		await StructureDoor.play_enter(house)
	## Entry id resolves via InteriorCatalog (`player_house_*` → player_main).
	Game.try_enter_interior(house_id if house_id != &"" else &"player_house")
	_entering_look_house = false


func _on_finished() -> void:
	## `aID_retire_rcn_guide_wait`: wait until Nook EXIT_TURN → EXIT deletes himself.
	_end_demo_talk()
	if _finishing:
		return
	_finishing = true
	call_deferred("_finish_after_nook_retire")


func _finish_after_nook_retire() -> void:
	await _nook_retire_exit()
	if Game.intro_house_look_requested.is_connected(_on_intro_house_look):
		Game.intro_house_look_requested.disconnect(_on_intro_house_look)
	if _dialogue != null and _dialogue.has_signal("event_fired"):
		if _dialogue.event_fired.is_connected(_on_dialogue_event):
			_dialogue.event_fired.disconnect(_on_dialogue_event)
	Audio.stop_bgm()
	if _player != null and is_instance_valid(_player):
		if _player.has_method("set_cutscene_driven"):
			_player.call("set_cutscene_driven", false)
		_player.set_busy(false)
	_resume_follow_camera(true)
	Game.complete_intro_station()
	## Resume outdoor field BGM now that the intro slice is done.
	Audio.play_bgm(BgmCatalog.outdoor_id(Clock.hour, Game.weather))
	if _actors != null and is_instance_valid(_actors):
		_actors.queue_free()
		_actors = null
	queue_free()


func _nook_retire_exit() -> void:
	## `aNRG_exit_turn` then `aNRG_exit`: turn toward leave point, run off, Actor_delete.
	if _nook == null or not is_instance_valid(_nook):
		return
	if _player != null and is_instance_valid(_player):
		_player.set_busy(true)
	var goal: Vector3 = _nook_exit_goal()
	var to_goal: Vector3 = goal - _nook.global_position
	to_goal.y = 0.0
	if to_goal.length_squared() > 0.0001:
		_nook.rotation.y = atan2(to_goal.x, to_goal.z)
	_nook_play_wait()
	if get_tree() != null:
		await get_tree().create_timer(0.4).timeout
	if _nook == null or not is_instance_valid(_nook):
		return
	_nook_play_clip("npc_1_run1", true)
	var speed_mps: float = (
		IntroStationStage.NOOK_RUN_SPEED_GX
		* FieldCatalog.GX_TO_METERS
		* IntroStationStage.TICK_HZ
	)
	while is_instance_valid(_nook):
		var delta: float = get_process_delta_time()
		var remain: Vector3 = goal - _nook.global_position
		remain.y = 0.0
		var dist: float = remain.length()
		if dist < 0.25:
			break
		var step: float = minf(speed_mps * delta, dist)
		var dir: Vector3 = remain / dist
		_nook.global_position += dir * step
		_nook.rotation.y = atan2(dir.x, dir.z)
		await get_tree().process_frame
	if _nook != null and is_instance_valid(_nook):
		_nook.visible = false
		_nook.queue_free()
		_nook = null


func _nook_exit_goal() -> Vector3:
	## Decomp runs toward fixed east X=2240 with Z north or south of the plot.
	## Here: away from the house, biased east, ~220 GX.
	var from: Vector3 = _nook.global_position if _nook != null else Vector3.ZERO
	var away := Vector3(1.0, 0.0, 0.0)
	var house: Node3D = _claimed_house()
	if house != null:
		away = from - house.global_position
		away.y = 0.0
		if away.length_squared() < 0.0001:
			away = Vector3(1.0, 0.0, 0.0)
		else:
			away = away.normalized()
		away = (away + Vector3(1.25, 0.0, 0.0)).normalized()
	elif _player != null and is_instance_valid(_player):
		away = from - _player.global_position
		away.y = 0.0
		if away.length_squared() < 0.0001:
			away = Vector3(1.0, 0.0, 0.0)
		else:
			away = away.normalized()
	var goal: Vector3 = from + away * (220.0 * FieldCatalog.GX_TO_METERS)
	goal.y = from.y
	return goal
