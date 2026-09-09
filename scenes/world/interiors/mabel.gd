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

enum Pending { NONE, DESIGN, BOOK, TREND, LISTEN, GBA, TRADE, TRADE_PICK }
enum Roam { IDLE, APPROACH }

var _model: Node3D
var _body_anim: AnimationPlayer
var _face: NpcFace = NpcFace.new()
var _talking: bool = false
var _talked_today: bool = false
var _clip: String = ""
var _pending: Pending = Pending.NONE
## Shop display slot the player pressed A at (0-3 cloth, 4-7 umbrella).
var _trade_fixture: int = -1
## The chosen trade action: "display" / "buy" / "exchange".
var _trade_act: String = ""
## The player design slot being edited / named.
var _edit_slot: int = -1
## Sequential dialogue queue (sister cutscene, multi-part trend report).
var _line_queue: Array = []
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
## stand (decomp `player_buy` sets `buy_ut_idx`, then talks to Mabel →
## `aNNW_TALK_TRADE_CHECK`). `slot` is the shop display slot (0-3 cloth, 4-7 umbrella).
func begin_trade(slot: int, ctx: InteractionContext) -> bool:
	if Game == null or Game.designs == null:
		return false
	_trade_fixture = slot
	_pending = Pending.NONE
	var listener: Node3D = ctx.actor as Node3D if ctx != null else _player_node()
	_face_toward(listener.global_position if listener != null else global_position)
	_talked_today = true
	## Decomp `player_buy` talks with `talk_idx = aNNW_TALK_TRADE_CHECK` — straight
	## to the display menu, no 6-way.
	_flow_trade_menu()
	return true


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
	match str(event.get("op", "")):
		"needlework_menu":
			match str(event.get("choice", "")):
				"design": _pending = Pending.DESIGN
				"book": _pending = Pending.BOOK
				"trend": _pending = Pending.TREND
				"listen": _pending = Pending.LISTEN
				"gba": _pending = Pending.GBA
		"needlework_trade":
			_trade_act = str(event.get("act", ""))
			_pending = Pending.TRADE_PICK


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
		Pending.TRADE: _flow_trade_menu()
		Pending.TRADE_PICK: _flow_trade_pick()
		_:
			_trade_fixture = -1
			_trade_act = ""


# --- sub-flows --------------------------------------------------------------

## `aNNW_talk_design_check` → `DESIGN_WHICH` → `DESIGN_OPEN` (`mSM_OVL_NEEDLEWORK`,
## `mNW_OPEN_DESIGN`) → editor → `DESIGN_OPEN3` (`mSM_OVL_LEDIT` name entry).
func _flow_make_design() -> void:
	if Game.inventory != null and _wallet() < NeedleworkTalk.DESIGN_PRICE:
		_say_line("A new design is %d Bells, and it looks like you're a little short. Come back soon!" % NeedleworkTalk.DESIGN_PRICE)
		return
	var list_ui: Node = _grp("design_list_ui")
	if list_ui != null and list_ui.has_method("open"):
		list_ui.call("open", "pick_edit", Callable(self, "_on_design_slot_chosen"))
		return
	Game.post_notice("Mabel: The design editor isn't ready yet.")


func _on_design_slot_chosen(slot: int) -> void:
	if slot < 0:
		return
	if Game.inventory != null:
		Game.inventory.spend_bells(NeedleworkTalk.DESIGN_PRICE)
	_edit_slot = slot
	var editor: Node = _grp("design_ui")
	if editor != null and editor.has_method("open"):
		editor.call("open", slot, Callable(self, "_on_editor_done"))


func _on_editor_done(slot: int, saved: bool) -> void:
	if not saved or slot < 0 or Game.designs == null:
		return
	## `aNNW_talk_design_open3` — name the freshly-saved design.
	var d: DesignPattern = Game.designs.player[Game.designs.resolved_index(slot)]
	var initial: String = d.name if d != null and d.name != "blank" else ""
	var name_ui: Node = _grp("name_entry_ui")
	if name_ui != null and name_ui.has_method("open"):
		name_ui.call("open", initial, Callable(self, "_on_name_entered"))


func _on_name_entered(text: String) -> void:
	if _edit_slot < 0 or Game.designs == null:
		return
	var d: DesignPattern = Game.designs.player[Game.designs.resolved_index(_edit_slot)]
	if d != null:
		d.name = text
		d.clamp_name()
	Game.designs.changed.emit()
	DesignTexture.clear_cache()
	if Game.worn_design_slot == _edit_slot:
		Game.design_changed.emit()
	_edit_slot = -1
	_say_line("\"%s\" — I love it! It's all yours." % text)


func _flow_design_book() -> void:
	var list_ui: Node = _grp("design_list_ui")
	if list_ui != null and list_ui.has_method("open"):
		list_ui.call("open", "manage", Callable())
		return
	Game.post_notice("Mabel: The design book isn't ready yet.")


## `aNNW_talk_trend_cloth` — reports the top cloth trend then the top umbrella trend.
func _flow_trend() -> void:
	if Game == null or Game.designs == null:
		return
	var cloth: Array = Game.designs.trend_top(false, _rng)
	var umb: Array = Game.designs.trend_top(true, _rng)
	_line_queue = [
		{"text": NeedleworkTalk.trend_line(Game.designs.shop[cloth[0] & 7].name, int(cloth[1]), false), "speaker": "Mabel"},
		{"text": NeedleworkTalk.trend_line(Game.designs.shop[umb[0] & 7].name, int(umb[1]), true), "speaker": "Mabel"},
	]
	_flush_queue()


## `aNNW_talk_listen_sister*` — the two-person Mabel/Sable story cutscene.
func _flow_listen() -> void:
	if Game == null or Game.designs == null:
		return
	Game.designs.listened_flag = true
	var first_of_day := Game.designs.sable_last_date != _today()
	if first_of_day:
		Game.designs.tick_sable_day(_today())
	var row := NeedleworkTalk.pick_story_row(Game.designs.sable_days, first_of_day, _rng)
	var ids := NeedleworkTalk.story_line_ids(row, _rng)
	_line_queue.clear()
	for i in ids.size():
		var data: DialogueData = NeedleworkTalk.line(ids[i])
		var txt: String = _first_line(data) if data != null else ""
		if txt.strip_edges().replace(".", "").replace("…", "").strip_edges().is_empty():
			txt = _fallback_story_line(i)
		_line_queue.append({"text": txt, "speaker": "Sable" if (i % 2 == 1) else "Mabel"})
	if _line_queue.is_empty():
		_line_queue.append({"text": "Sable's a little shy, but she's warming up to you.", "speaker": "Mabel"})
	_flush_queue()


func _flow_gba() -> void:
	_say_line("Oh — you'd need a Game Boy Advance hooked up for that. Maybe another time!")


## `aNNW_talk_trade_check` — the 4-way display menu (`aNNW_set_...`).
func _flow_trade_menu() -> void:
	if _trade_fixture < 0 or Game.designs == null:
		return
	var is_umb := _trade_fixture >= DesignBook.CLOTH_SLOTS
	var d: DesignPattern = Game.designs.shop[_trade_fixture & 7]
	var thing := "umbrella" if is_umb else "outfit"
	var data := DialogueData.from_dict({
		"id": "mabel_trade", "start": "start",
		"nodes": {
			"start": {"type": "line", "text": "That's the \"%s\" %s. What would you like to do?" % [d.name, thing], "next": "menu"},
			"menu": {"type": "choice", "prompt": "", "options": [
				{"text": "Put one of my designs here.", "events": [{"op": "needlework_trade", "act": "display"}]},
				{"text": "I'd like this design.", "events": [{"op": "needlework_trade", "act": "buy"}]},
				{"text": "Let's trade designs.", "events": [{"op": "needlework_trade", "act": "exchange"}]},
				{"text": "Never mind.", "goto": "bye"},
			]},
			"bye": {"type": "line", "text": "No trouble at all. Take your time!"},
		},
	})
	var ui: Node = _grp("dialogue_ui")
	if ui == null or not ui.has_method("play"):
		_trade_fixture = -1
		return
	_start_talk_session(_player_node())
	_bind_session(ui)
	ui.call("play", data, _make_ctx())


func _flow_trade_pick() -> void:
	var list_ui: Node = _grp("design_list_ui")
	if list_ui != null and list_ui.has_method("open"):
		list_ui.call("open", "pick_trade", Callable(self, "_on_trade_slot_chosen"))
		return
	_trade_fixture = -1


## `aNNW_talk_trade_close*` — apply the chosen op and report.
func _on_trade_slot_chosen(player_slot: int) -> void:
	var fixture := _trade_fixture
	var act := _trade_act
	_trade_fixture = -1
	_trade_act = ""
	if player_slot < 0 or fixture < 0 or Game.designs == null:
		return
	var affected := Game.designs.resolved_index(player_slot)
	match act:
		"display":
			Game.designs.copy_player_to_shop(fixture, player_slot)
		"buy":
			Game.designs.buy_shop_into_player(fixture, player_slot)
			Game.designs.trend_delete(fixture)
		"exchange":
			Game.designs.exchange(fixture, player_slot)
		_:
			return
	Audio.play_se(&"cursol")
	DesignTexture.clear_cache()
	var shown: String = Game.designs.shop[fixture & 7].name
	_say_line(NeedleworkTalk.trade_result_line(act, shown))
	if act != "display" and Game.worn_design_slot >= 0 \
			and Game.designs.resolved_index(Game.worn_design_slot) == affected:
		Game.design_changed.emit()


# --- sequential dialogue queue -------------------------------------------

func _flush_queue() -> void:
	if _line_queue.is_empty():
		return
	var entry: Dictionary = _line_queue.pop_front()
	var ui: Node = _grp("dialogue_ui")
	if ui == null:
		Game.post_notice("%s: %s" % [entry.get("speaker", "Mabel"), entry.get("text", "")])
		_flush_queue()
		return
	_start_talk_session(_player_node())
	if ui.has_signal("closed") and not ui.is_connected("closed", _on_queue_closed):
		ui.connect("closed", _on_queue_closed, CONNECT_ONE_SHOT)
	if ui.has_method("say"):
		ui.call("say", str(entry.get("text", "")), str(entry.get("speaker", "Mabel")))


func _on_queue_closed() -> void:
	_talking = false
	TalkCamera.end(get_tree())
	if not _line_queue.is_empty():
		_flush_queue()


func _first_line(data: DialogueData) -> String:
	if data == null:
		return ""
	data.ensure_loaded()
	var rec: Dictionary = data.node(data.start)
	return str(rec.get("text", ""))


func _fallback_story_line(i: int) -> String:
	var mabel := [
		"Sable used to sew all day and barely say a word.",
		"She's my little sister — talented, but so shy.",
		"You've really made her day, you know.",
	]
	var sable := [
		"...Oh! Hello. You're becoming a regular around here.",
		"I suppose I don't mind the company. It's... nice.",
		"Thank you for stopping by. Truly.",
	]
	return (sable if i % 2 == 1 else mabel)[(i / 2) % 3]


func _wallet() -> int:
	if Game == null or Game.inventory == null:
		return 0
	return Game.inventory.wallet


func _grp(g: String) -> Node:
	return get_tree().get_first_node_in_group(g) if get_tree() != null else null


func _player_node() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D if get_tree() != null else null


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
