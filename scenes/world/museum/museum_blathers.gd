extends StaticBody3D

## Blathers in the museum entrance (`ac_npc_curator`). Wait anim + talk/donate.
## Nocturnal (`ac_npc_curator` sleep schedule): drowsy 05:00–19:00, alert at night.

const ANIM_WAIT := "npc_1_wait1"
## Sleep clip suffix candidates (`_resolve_clip` fuzzy-matches; falls back to wait).
const ANIM_SLEEP := "npc_1_sleep1"
const GREETING_ID := &"blathers_greeting"
## Museum is drowsy while the sun is up (`aNPC_CURATOR_isSleepTime`-ish window).
const DROWSY_START_HOUR := 5
const DROWSY_END_HOUR := 19

var _model: Node3D
var _body_anim: AnimationPlayer
var _face: NpcFace = NpcFace.new()
var _talking: bool = false
var _clip: String = ""
var _listener: Node3D = null
var _pending_menu: StringName = &""


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("museum_set")
	collision_layer = 1
	collision_mask = 0
	_ensure_collision()
	_ensure_visual()
	_ensure_interact()


func _process(delta: float) -> void:
	var uttering: bool = false
	if _talking and get_tree() != null:
		var ui: Node = get_tree().get_first_node_in_group("dialogue_ui")
		if ui != null and ui.has_method("is_uttering"):
			uttering = bool(ui.call("is_uttering"))
	_face.tick(delta, uttering)
	if _talking:
		_face_player()
	else:
		_play_clip(_idle_clip(), true)


## Slumped sleep pose while drowsy when the visual has one; otherwise the wait loop.
func _idle_clip() -> String:
	if _is_drowsy() and not _resolve_clip(ANIM_SLEEP).is_empty():
		return ANIM_SLEEP
	return ANIM_WAIT


## Nocturnal: slumped and sleepy during daylight, alert after dusk (`ac_npc_curator`).
func _is_drowsy() -> bool:
	if not Engine.is_editor_hint() and Clock != null:
		return Clock.in_hour_window(DROWSY_START_HOUR, DROWSY_END_HOUR)
	return false


func get_interactions(ctx: InteractionContext) -> Array[Interaction]:
	var out: Array[Interaction] = [Interaction.of(Interaction.TALK, "Talk to Blathers", 20)]
	var item: ItemData = _selected_item(ctx)
	if item != null and Game != null and Game.museum != null:
		if item.id == &"fossil":
			out.append(Interaction.of(Interaction.DONATE, "Show Blathers the fossil", 25))
		elif Game.museum.display_info_for_item(item) == MuseumBook.DisplayInfo.CAN_DONATE:
			out.append(Interaction.of(Interaction.DONATE, "Donate %s" % item.display_name, 25))
	return out


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null or Game == null:
		return false
	match action.id:
		Interaction.TALK:
			return _begin_talk(ctx)
		Interaction.DONATE:
			return _begin_donate(ctx)
		_:
			return false


func _begin_talk(ctx: InteractionContext) -> bool:
	var listener: Node3D = ctx.actor as Node3D if ctx != null else null
	_listener = listener
	_pending_menu = &""
	_face_toward(listener.global_position if listener != null else global_position)
	var data: DialogueData = DialogueCatalog.conversation(GREETING_ID)
	var talk_ctx: DialogueContext = _make_talk_ctx()
	var ui: Node = get_tree().get_first_node_in_group("dialogue_ui") if get_tree() != null else null
	if ui != null and data != null and ui.has_method("play"):
		if ui.has_method("is_open") and bool(ui.call("is_open")) and ui.has_method("close"):
			ui.call("close")
		_start_talk_session(listener)
		_bind_talk_end(ui)
		_bind_events(ui)
		ui.call("play", data, talk_ctx)
	elif ui != null and ui.has_method("say"):
		_start_talk_session(listener)
		_bind_talk_end(ui)
		ui.call(
			"say",
			"Hoo — welcome to the museum. Bring me fossils, art, fish, or bugs!",
			"Blathers"
		)
	else:
		Game.post_notice("Blathers: Hoo — welcome to the museum!")
	_mark_greeted()
	return true


## Greeting context: nocturnal state + museum-progress flags the JSON branches read.
func _make_talk_ctx() -> DialogueContext:
	var talk_ctx: DialogueContext = DialogueContext.from_game()
	talk_ctx.speaker_name = "Blathers"
	## Special NPC (`l_sp_actor_name`): animalese at sound spec 2, male nameplate tint.
	talk_ctx.voice_mode = DialogueVoice.Mode.ANIMALESE
	talk_ctx.sound_spec = 2
	talk_ctx.speaker_sex = 0
	talk_ctx.already_talked = _greeted_today()
	var book: MuseumBook = Game.museum if Game != null else null
	## String flags (JSON `var_eq` compares with `str()`; numeric literals parse as float).
	talk_ctx.set_var("museum_empty", "yes" if book != null and book.count_all() == 0 else "no")
	talk_ctx.set_var("museum_complete", "yes" if book != null and book.is_complete() else "no")
	return talk_ctx


func _greet_day_key() -> String:
	if Clock == null:
		return ""
	return "%04d-%02d-%02d" % [Clock.year, Clock.month, Clock.day]


func _greeted_today() -> bool:
	if Game == null:
		return false
	return str(Game.dialogue_vars.get("blathers_greet_day", "")) == _greet_day_key()


func _mark_greeted() -> void:
	if Game != null:
		Game.dialogue_vars["blathers_greet_day"] = _greet_day_key()


## Pocket "Donate X" interaction — go straight to the donate-select pockets.
func _begin_donate(ctx: InteractionContext) -> bool:
	_listener = ctx.actor as Node3D if ctx != null else _listener
	_face_toward(_listener.global_position if _listener != null else global_position)
	_open_donate_pockets()
	return true


## Blathers opens the player's pockets to receive a donation (`mMmd` IV_OPEN). Each item
## worth offering shows a "Donate" tag; picking one books the outcome and Blathers
## responds. With no pockets UI (headless), fall back to the dialogue-list picker.
func _open_donate_pockets() -> void:
	if Game == null:
		return
	if not Game.museum_donate_resolved.is_connected(_on_donate_resolved):
		Game.museum_donate_resolved.connect(_on_donate_resolved)
	var inv_ui: Node = get_tree().get_first_node_in_group("inventory_ui") if get_tree() != null else null
	if inv_ui == null or not inv_ui.has_method("open"):
		_play_donate_conversation(&"")
		return
	Game.request_museum_donation()


func _on_donate_resolved(donated: bool) -> void:
	if Game != null and Game.museum_donate_resolved.is_connected(_on_donate_resolved):
		Game.museum_donate_resolved.disconnect(_on_donate_resolved)
	if not donated:
		return
	_play_donate_outcome()


## Blathers' response to the item just picked in the pockets (`Game.museum_donate_result`).
func _play_donate_outcome() -> void:
	var result: Dictionary = Game.museum_donate_result if Game != null else {}
	var item_id: StringName = StringName(str(result.get("item_id", "")))
	var ui: Node = get_tree().get_first_node_in_group("dialogue_ui") if get_tree() != null else null
	var data: DialogueData = MuseumDialogue.build_outcome(item_id, result)
	if ui == null or data == null or not ui.has_method("play"):
		_say_line(String(result.get("message", "Thank you.")))
		return
	if ui.has_method("is_open") and bool(ui.call("is_open")) and ui.has_method("close"):
		ui.call("close")
	_start_talk_session(_listener)
	_bind_talk_end(ui)
	_bind_events(ui)
	if item_id != &"" and bool(result.get("ok", false)):
		_play_putaway(item_id)
	ui.call("play", data, _make_talk_ctx())


func _start_talk_session(listener: Node3D) -> void:
	_talking = true
	## Decomp `Camera2_request_main_talk(play, player, npc)` — speaker = player.
	if listener != null:
		TalkCamera.begin(listener, self, get_tree())
	_play_clip(ANIM_WAIT, true)


func _bind_talk_end(ui: Node) -> void:
	if ui == null or not ui.has_signal("closed"):
		return
	if ui.closed.is_connected(_on_talk_closed):
		ui.closed.disconnect(_on_talk_closed)
	ui.closed.connect(_on_talk_closed, CONNECT_ONE_SHOT)


func _bind_events(ui: Node) -> void:
	if ui == null or not ui.has_signal("event_fired"):
		return
	if not ui.event_fired.is_connected(_on_dialogue_event):
		ui.event_fired.connect(_on_dialogue_event)


## Menu choices (`{op:"museum_menu"}`) and the donate-item hand-over both arrive here.
func _on_dialogue_event(event: Dictionary) -> void:
	match String(event.get("op", "")):
		"museum_menu":
			_pending_menu = StringName(str(event.get("choice", "")))
		"donate_commit":
			_play_putaway(StringName(str(event.get("item", ""))))


func _on_talk_closed() -> void:
	_talking = false
	TalkCamera.end(get_tree())
	var ui: Node = get_tree().get_first_node_in_group("dialogue_ui") if get_tree() != null else null
	if ui != null and ui.has_signal("event_fired") and ui.event_fired.is_connected(_on_dialogue_event):
		ui.event_fired.disconnect(_on_dialogue_event)
	_play_clip(_idle_clip(), true)
	var menu: StringName = _pending_menu
	_pending_menu = &""
	match menu:
		&"donate", &"donate_again":
			_open_donate_pockets()


## Item-by-item donation conversation (`MuseumDialogue`). `preselect` opens on that item.
func _play_donate_conversation(preselect: StringName) -> void:
	var ui: Node = get_tree().get_first_node_in_group("dialogue_ui") if get_tree() != null else null
	var data: DialogueData = MuseumDialogue.build_donate(preselect)
	if ui == null or data == null or not ui.has_method("play"):
		_say_line("Hoo — bring me a fossil, some art, a fish, or a bug, and I'll see it displayed.")
		return
	if ui.has_method("is_open") and bool(ui.call("is_open")) and ui.has_method("close"):
		ui.call("close")
	var talk_ctx: DialogueContext = _make_talk_ctx()
	_start_talk_session(_listener)
	_bind_talk_end(ui)
	_bind_events(ui)
	ui.call("play", data, talk_ctx)


## `handOverItem` put-away demo while the examine line types.
func _play_putaway(item_id: StringName) -> void:
	if item_id == &"" or _listener == null:
		return
	HandOver.player_gives_to_npc(_listener, self, item_id)


func _say_line(text: String) -> void:
	var ui: Node = get_tree().get_first_node_in_group("dialogue_ui") if get_tree() != null else null
	if ui != null and ui.has_method("say"):
		if ui.has_method("is_open") and bool(ui.call("is_open")) and ui.has_method("close"):
			ui.call("close")
		_start_talk_session(_listener)
		_bind_talk_end(ui)
		ui.call("say", text, "Blathers")
	elif Game != null:
		Game.post_notice("Blathers: %s" % text)


func _face_player() -> void:
	if get_tree() == null:
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	if player is Node3D:
		_face_toward((player as Node3D).global_position)


func _face_toward(world_pos: Vector3) -> void:
	var to: Vector3 = world_pos - global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	var yaw: float = atan2(to.x, to.z)
	if _model != null:
		_model.rotation.y = yaw
	else:
		rotation.y = yaw


func _selected_item(ctx: InteractionContext) -> ItemData:
	var inv: Inventory = ctx.inventory if ctx != null and ctx.inventory != null else Game.inventory
	if inv == null:
		return null
	var slot: InventorySlot = inv.selected_slot()
	if slot == null or slot.is_empty():
		return null
	return ItemCatalog.get_item(slot.item.item_id)


func _ensure_collision() -> void:
	if get_node_or_null("CollisionShape3D") != null:
		return
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.8, 1.0)
	shape.shape = box
	shape.position = Vector3(0.0, 0.9, 0.0)
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
	box.size = Vector3(1.6, 2.0, 1.6)
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
	var vis: Node3D = GeneratedVisual.attach_villager(_model, &"owl")
	if vis == null:
		var mesh := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.35
		capsule.height = 1.4
		mesh.mesh = capsule
		mesh.position.y = 0.9
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.55, 0.42, 0.28)
		mesh.material_override = mat
		_model.add_child(mesh)
		return
	_body_anim = GeneratedVisual.find_animation_player(vis)
	_face.bind(vis, &"owl")
	_play_clip(ANIM_WAIT, true)


func _play_clip(suffix: String, loop: bool) -> void:
	if _body_anim == null:
		return
	var clip := _resolve_clip(suffix)
	if clip.is_empty():
		return
	if clip == _clip and _body_anim.is_playing():
		return
	_clip = clip
	var animation: Animation = _body_anim.get_animation(clip)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	_body_anim.speed_scale = 1.0
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
