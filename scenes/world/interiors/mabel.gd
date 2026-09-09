extends CharacterBody3D

## Mabel — the Able Sisters shopkeeper (`ac_npc_needlework` / `SP_NPC_NEEDLEWORK0`,
## skeleton `hgh_1`). Runs the design / trade / trend / listen menu
## (`aNNW_set_6_ways`, `ac_npc_needlework_talk.c_inc:305`) and walks up to greet the
## player (`aNNW_MY_PROC_*`, `_schedule.c_inc:329`).

const SPECIES := &"hgh"
const ANIM_WAIT := "npc_1_wait1"
const ANIM_WALK := "npc_1_walk1"
const MENU_ID := &"mabel_menu"

## `aNNW_my_proc_wait`: chase when the player is ≥ 120 GX (6 m) away, stop within
## ~2 m (`aNNW_my_proc_player` runs to the player's own position).
const FOLLOW_RANGE := 6.0
const STOP_RANGE := 1.9
const MOVE_SPEED := 2.4  ## `aNPC_ACT_RUN`

enum Pending { NONE, DESIGN, BOOK, TREND, LISTEN, GBA, TRADE }
enum Roam { IDLE, APPROACH }

var _model: Node3D
var _body_anim: AnimationPlayer
var _face: NpcFace = NpcFace.new()
var _talking: bool = false
var _talked_today: bool = false
var _clip: String = ""
var _pending: Pending = Pending.NONE
var _trade_slot: int = -1
var _active_ui: Node = null
var _rng := RandomNumberGenerator.new()
var _roam: Roam = Roam.IDLE
var _home: Vector3
var _greeted_at := 0.0


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("needlework_set")
	add_to_group("needlework_mabel")
	## Layer 4 (characters): the player collides with her (mask 5 = 1|4).
	## Mask 1 keeps her out of the furniture / walls.
	collision_layer = 4
	collision_mask = 1
	_rng.randomize()
	_ensure_collision()
	_ensure_visual()
	_ensure_interact()
	_home = global_position


func _process(delta: float) -> void:
	var uttering: bool = false
	if _talking and get_tree() != null:
		var ui: Node = get_tree().get_first_node_in_group("dialogue_ui")
		if ui != null and ui.has_method("is_uttering"):
			uttering = bool(ui.call("is_uttering"))
	_face.tick(delta, uttering)


func _physics_process(delta: float) -> void:
	if _talking:
		velocity = Vector3.ZERO
		_face_player()
		return
	var roam := _roam_velocity(delta)
	velocity = Vector3(roam.x, 0.0, roam.z)
	move_and_slide()
	if roam.length() > 0.05:
		_face_toward(global_position + roam)
		_play_clip(ANIM_WALK, true)
	else:
		_play_clip(ANIM_WAIT, true)


## `aNNW_MY_PROC_*` boiled down: chase the player, stop just short, idle otherwise.
func _roam_velocity(_delta: float) -> Vector3:
	if get_tree() == null or Game == null:
		return Vector3.ZERO
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return Vector3.ZERO
	var dlg: Node = get_tree().get_first_node_in_group("dialogue_ui")
	if dlg != null and dlg.has_method("is_open") and bool(dlg.call("is_open")):
		return Vector3.ZERO
	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	match _roam:
		Roam.IDLE:
			_face_toward(player.global_position)
			if dist >= FOLLOW_RANGE:
				_roam = Roam.APPROACH
			return Vector3.ZERO
		Roam.APPROACH:
			if dist <= STOP_RANGE:
				_roam = Roam.IDLE
				_face_toward(player.global_position)
				_maybe_greet()
				return Vector3.ZERO
			return to_player.normalized() * MOVE_SPEED
	return Vector3.ZERO


func _maybe_greet() -> void:
	## `aNNW_THINK_IKAGADESYOU` — "How's it going?" bark, rate-limited.
	var now := Time.get_ticks_msec() / 1000.0
	if now - _greeted_at < 25.0 or _talked_today:
		return
	_greeted_at = now
	if Game != null:
		Game.post_notice("Mabel: How's it going? Let me know if you need anything!")


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	return [Interaction.of(Interaction.TALK, "Talk to Mabel", 20)]


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.TALK or Game == null:
		return false
	return _begin_talk(ctx)


## Called by an `able_fixture` when the player presses A at a mannequin / umbrella
## stand (decomp `player_buy` sets `buy_ut_idx`, then talks to Mabel).
func begin_trade(slot: int, ctx: InteractionContext) -> bool:
	_trade_slot = slot
	var ok := _begin_talk(ctx)
	## Route straight into the trade branch after the greeting.
	_pending = Pending.TRADE
	return ok


func _begin_talk(ctx: InteractionContext) -> bool:
	var listener: Node3D = ctx.actor as Node3D if ctx != null else null
	_face_toward(listener.global_position if listener != null else global_position)
	_pending = Pending.NONE
	var data: DialogueData = DialogueCatalog.conversation(MENU_ID)
	var talk_ctx: DialogueContext = _make_ctx()
	talk_ctx.already_talked = _talked_today
	var ui: Node = get_tree().get_first_node_in_group("dialogue_ui") if get_tree() != null else null
	if ui != null and data != null and ui.has_method("play"):
		if ui.has_method("is_open") and bool(ui.call("is_open")) and ui.has_method("close"):
			ui.call("close")
		_start_talk_session(listener)
		_bind_session(ui)
		ui.call("play", data, talk_ctx)
	elif ui != null and ui.has_method("say"):
		_start_talk_session(listener)
		_bind_end(ui)
		ui.call("say", "Welcome to Able Sisters!", "Mabel")
	else:
		Game.post_notice("Mabel: Welcome to Able Sisters!")
	_talked_today = true
	return true


func _make_ctx() -> DialogueContext:
	var c: DialogueContext = DialogueContext.from_game()
	c.speaker_name = "Mabel"
	c.speaker_sex = 1
	c.voice_mode = DialogueVoice.Mode.ANIMALESE
	c.sound_spec = 4
	c.frees = PackedStringArray(["Mabel", "Sable"])
	return c


func _bind_session(ui: Node) -> void:
	_active_ui = ui
	if ui.has_signal("event_fired") and not ui.event_fired.is_connected(_on_dialogue_event):
		ui.event_fired.connect(_on_dialogue_event)
	if ui.has_signal("closed"):
		if ui.is_connected("closed", _on_talk_closed):
			ui.disconnect("closed", _on_talk_closed)
		ui.connect("closed", _on_talk_closed, CONNECT_ONE_SHOT)


func _bind_end(ui: Node) -> void:
	if ui == null or not ui.has_signal("closed") or ui.is_connected("closed", _on_talk_closed):
		return
	ui.connect("closed", _on_talk_closed, CONNECT_ONE_SHOT)


func _on_dialogue_event(event: Dictionary) -> void:
	if str(event.get("op", "")) != "needlework_menu":
		return
	match str(event.get("choice", "")):
		"design": _pending = Pending.DESIGN
		"book": _pending = Pending.BOOK
		"trend": _pending = Pending.TREND
		"listen": _pending = Pending.LISTEN
		"gba": _pending = Pending.GBA


func _on_talk_closed() -> void:
	if _active_ui != null and _active_ui.has_signal("event_fired"):
		if _active_ui.event_fired.is_connected(_on_dialogue_event):
			_active_ui.event_fired.disconnect(_on_dialogue_event)
	_active_ui = null
	_talking = false
	TalkCamera.end(get_tree())
	var next: Pending = _pending
	_pending = Pending.NONE
	match next:
		Pending.DESIGN: _flow_make_design()
		Pending.BOOK: _flow_design_book()
		Pending.TREND: _flow_trend()
		Pending.LISTEN: _flow_listen()
		Pending.GBA: _flow_gba()
		Pending.TRADE: _flow_trade()
		_: _trade_slot = -1


# --- sub-flows --------------------------------------------------------------

func _flow_make_design() -> void:
	if Game.inventory != null and Game.inventory.wallet < NeedleworkTalk.DESIGN_PRICE:
		_say_msg(NeedleworkTalk.MSG_DESIGN_NO_MONEY)
		return
	var list_ui: Node = get_tree().get_first_node_in_group("design_list_ui") if get_tree() != null else null
	if list_ui != null and list_ui.has_method("open"):
		list_ui.call("open", "pick_edit", Callable(self, "_on_design_slot_chosen"))
		return
	Game.post_notice("Mabel: The design editor isn't ready yet.")


func _on_design_slot_chosen(slot: int) -> void:
	if slot < 0:
		return
	if Game.inventory != null:
		Game.inventory.spend_bells(NeedleworkTalk.DESIGN_PRICE)
	var editor: Node = get_tree().get_first_node_in_group("design_ui") if get_tree() != null else null
	if editor != null and editor.has_method("open"):
		editor.call("open", slot)


func _flow_design_book() -> void:
	var list_ui: Node = get_tree().get_first_node_in_group("design_list_ui") if get_tree() != null else null
	if list_ui != null and list_ui.has_method("open"):
		list_ui.call("open", "manage", Callable())
		return
	Game.post_notice("Mabel: The design book isn't ready yet.")


func _flow_trend() -> void:
	_say_line(_trend_line())


func _flow_listen() -> void:
	if Game.designs != null:
		Game.designs.listened_flag = true
	_play_sister_story()


func _flow_gba() -> void:
	_say_msg(NeedleworkTalk.MSG_GBA_NOT_CONNECTED)


func _flow_trade() -> void:
	var slot: int = _trade_slot
	_trade_slot = -1
	if slot < 0 or Game.designs == null:
		return
	var list_ui: Node = get_tree().get_first_node_in_group("design_list_ui") if get_tree() != null else null
	if list_ui != null and list_ui.has_method("open"):
		list_ui.call("open", "pick_trade", Callable(self, "_on_trade_slot_chosen").bind(slot))
		return
	## No picker yet — buy the shop design into the first blank player slot.
	var d: DesignPattern = Game.designs.shop[slot & 7]
	Game.post_notice("Mabel: This is \"%s\". Come back when the design book's open!" % d.name)


func _on_trade_slot_chosen(player_slot: int, shop_slot: int) -> void:
	if player_slot < 0 or Game.designs == null:
		return
	## Default action: copy the shop design into the chosen player slot
	## (`TRADE_CLOSE3`). Exchange / put-on-mannequin variants come with the
	## full trade menu.
	Game.designs.buy_shop_into_player(shop_slot, player_slot)
	Audio.play_se(&"cursol")
	_say_msg(NeedleworkTalk.MSG_TRADE_BUY_DESIGN)
	if Game.worn_design_slot == player_slot:
		Game.design_changed.emit()


func _trend_line() -> String:
	if Game == null or Game.designs == null:
		return "Nothing's really caught on yet this season."
	## Count villagers wearing each of the 4 shop clothing designs.
	var best_name := ""
	var best_count := 0
	for i in DesignBook.CLOTH_SLOTS:
		var count := _villagers_wearing_design(i)
		if count > best_count:
			best_count = count
			best_name = Game.designs.shop[i].name
	if best_count == 0:
		return "Hmm, no home-grown design has really taken off yet."
	if best_count == 1:
		return "One person's wearing \"%s\" around town — it's just starting!" % best_name
	if best_count < 5:
		return "\"%s\" is catching on — I've seen a few people in it!" % best_name
	return "\"%s\" is THE look this season. Everyone's wearing it!" % best_name


func _villagers_wearing_design(_shop_cloth_idx: int) -> int:
	## TODO: villagers do not wear custom designs yet (`animal->cloth == RSV_CLOTH`).
	return 0


func _play_sister_story() -> void:
	if Game == null or Game.designs == null:
		return
	var first_of_day := Game.designs.sable_last_date != _today()
	var row := NeedleworkTalk.pick_story_row(Game.designs.sable_days, first_of_day, _rng)
	var ids := NeedleworkTalk.story_line_ids(row, _rng)
	if ids.is_empty():
		return
	var ui: Node = get_tree().get_first_node_in_group("dialogue_ui") if get_tree() != null else null
	if ui == null:
		return
	# Alternate speaker Mabel / Sable per line (`aNNW_talk_ane_*`).
	var texts: Array = []
	for i in ids.size():
		var line: DialogueData = NeedleworkTalk.line(ids[i])
		if line != null:
			texts.append({"data": line, "speaker": "Sable" if (i % 2 == 1) else "Mabel"})
	if texts.is_empty():
		return
	_start_talk_session(get_tree().get_first_node_in_group("player") as Node3D)
	_bind_end(ui)
	# Play the first; the rest chain via the runner's own `next` if present, else
	# just show the opener (full multi-line chaining is a Phase 3 polish item).
	var ctx := _make_ctx()
	ctx.speaker_name = texts[0]["speaker"]
	ui.call("play", texts[0]["data"], ctx)


func _say_msg(msg_id: int) -> void:
	var data: DialogueData = NeedleworkTalk.line(msg_id)
	if data == null:
		return
	var ui: Node = get_tree().get_first_node_in_group("dialogue_ui") if get_tree() != null else null
	if ui == null or not ui.has_method("play"):
		return
	_start_talk_session(get_tree().get_first_node_in_group("player") as Node3D)
	_bind_end(ui)
	ui.call("play", data, _make_ctx())


func _say_line(text: String) -> void:
	var ui: Node = get_tree().get_first_node_in_group("dialogue_ui") if get_tree() != null else null
	if ui != null and ui.has_method("say"):
		_start_talk_session(get_tree().get_first_node_in_group("player") as Node3D)
		_bind_end(ui)
		ui.call("say", text, "Mabel")
	elif Game != null:
		Game.post_notice("Mabel: %s" % text)


func _today() -> String:
	return "%04d-%02d-%02d" % [Clock.year, Clock.month, Clock.day]


# --- boilerplate -----------------------------------------------------------

func _start_talk_session(listener: Node3D) -> void:
	_talking = true
	if listener != null:
		TalkCamera.begin(listener, self, get_tree())
	_play_clip(ANIM_WAIT, true)


func _face_player() -> void:
	var player: Node = get_tree().get_first_node_in_group("player") if get_tree() != null else null
	if player is Node3D:
		_face_toward((player as Node3D).global_position)


func _face_toward(target: Vector3) -> void:
	var to: Vector3 = target - global_position
	to.y = 0.0
	if to.length_squared() > 0.0001:
		rotation.y = atan2(to.x, to.z)


func _ensure_collision() -> void:
	if get_node_or_null("CollisionShape3D") != null:
		return
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.5
	shape.shape = cap
	shape.position = Vector3(0.0, 0.75, 0.0)
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
	var vis: Node3D = GeneratedVisual.attach_villager(_model, SPECIES)
	if vis == null:
		var mesh := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.32
		capsule.height = 1.3
		mesh.mesh = capsule
		mesh.position.y = 0.85
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.62, 0.5, 0.7)
		mesh.material_override = mat
		_model.add_child(mesh)
		return
	_body_anim = GeneratedVisual.find_animation_player(vis)
	_face.bind(vis, SPECIES)
	_play_clip(ANIM_WAIT, true)


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
