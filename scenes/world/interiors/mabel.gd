extends CharacterBody3D

## Mabel — the Able Sisters shopkeeper (`ac_npc_needlework` / `SP_NPC_NEEDLEWORK0`,
## skeleton `hgh_1`). Runs the design / album / trend / listen / GBA menu
## (`aNNW_set_6_ways`, `ac_npc_needlework_talk.c_inc`), walks up to greet the player
## (`aNNW_MY_PROC_*`, `_schedule.c_inc`), handles the display trades when the player
## presses A at a mannequin / stand, chimes in on Sable's stories (`aNNW_THINK_AINOTE`),
## and sees the player off at the door (`aNNW_THINK_10`, `player_go_away`).

const SPECIES := &"hgh"
const ANIM_WAIT := "npc_1_wait1"
const ANIM_WALK := "npc_1_walk1"
const MENU_ID := &"mabel_menu"

## `aNNW_next_target`: run to the player when they are within ~115 GX (5.75 m) and
## in a reachable area; `aNNW_my_proc_player` runs to the player's own position and
## stops just short. She auto-greets on the first approach of a visit
## (`aNNW_force_talk_request` think 8 / 9).
const APPROACH_RANGE := 5.75
const STOP_RANGE := 1.7
const MOVE_SPEED := 2.4  ## `aNPC_ACT_RUN`

enum Pending { NONE, DESIGN, BOOK, TREND, LISTEN, GBA, TRADE_PICK, ACT }

var _model: Node3D
var _body_anim: AnimationPlayer
var _face: NpcFace = NpcFace.new()
var _talking: bool = false
var _talked_today: bool = false
var _clip: String = ""
var _pending: Pending = Pending.NONE
## Shop display slot the player pressed A at (0-3 cloth, 4-7 umbrella) — `buy_ut_idx`.
var _trade_fixture: int = -1
## The chosen trade action: "display" / "buy" / "exchange".
var _trade_act: String = ""
## Deferred action from a confirm dialogue (`needlework_act` event).
var _next_act: String = ""
## The player design slot being edited / named (`_9AE`).
var _edit_slot: int = -1
## Sequential line queue: `{text, speaker, focus}` entries, then `_after_queue`.
var _line_queue: Array = []
var _after_queue: Callable = Callable()
var _active_ui: DialogueOverlay = null
var _rng := RandomNumberGenerator.new()
var _home: Vector3
## `aNNW_force_talk_request` — Mabel starts the conversation herself the first time
## she reaches the player after they enter. Sticky for the visit.
var _auto_greeted := false
## Turned toward Sable for a story interjection (`aNNW_ainote_init`).
var _chiming: Node3D = null
## `aNNW_THINK_10` fired — the goodbye is said once and the player leaves.
var _bye_said := false


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
	if (_talking or _chiming != null) and get_tree() != null:
		uttering = DialogueOverlay.uttering_in(get_tree())
	_face.tick(delta, uttering)


func _physics_process(delta: float) -> void:
	if _chiming != null:
		velocity = Vector3.ZERO
		_face_toward(_chiming.global_position)
		_play_clip(ANIM_WAIT, true)
		return
	if _talking:
		velocity = Vector3.ZERO
		_face_player()
		return
	if _check_goodbye():
		return
	var roam := _roam_velocity(delta)
	velocity = Vector3(roam.x, 0.0, roam.z)
	move_and_slide()
	if roam.length() > 0.05:
		_face_toward(global_position + roam)
		_play_clip(ANIM_WALK, true)
	else:
		_play_clip(ANIM_WAIT, true)


## `aNNW_my_proc_player` boiled down: run to the player while they're in range, stop
## just short, face them, and auto-greet on the first approach of the visit.
func _roam_velocity(_delta: float) -> Vector3:
	if get_tree() == null or Game == null:
		return Vector3.ZERO
	var player := Player.find(get_tree())
	if player == null:
		return Vector3.ZERO
	var dlg := DialogueOverlay.find(get_tree())
	if dlg != null and dlg.is_open():
		return Vector3.ZERO
	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	if dist > STOP_RANGE and dist < APPROACH_RANGE:
		return to_player.normalized() * MOVE_SPEED
	_face_toward(player.global_position)
	if dist <= STOP_RANGE and not _auto_greeted and not _talking and not _talked_today:
		_auto_greeted = true
		call_deferred("_begin_talk")
	return Vector3.ZERO


## `player_go_away` → `aNNW_THINK_10`: the player stands on the row in front of the
## exit strip facing it (`item_in_front == EXIT_DOOR1`). Mabel says goodbye without
## turning the player (`mDemo_Set_talk_turn(FALSE)`, normal camera) and the talk ends
## by leaving the shop (`aNNW_talk_byebye` → `aNNW_talk_exit`).
func _check_goodbye() -> bool:
	if _bye_said or Game == null or Game.block_auto_enter_doors or get_tree() == null:
		return false
	var dlg := DialogueOverlay.find(get_tree())
	if dlg != null and dlg.is_open():
		return false
	var player := Player.find(get_tree())
	if player == null or player.is_busy():
		return false
	var session: IndoorSession = Game.interior_session
	if session == null or session.grid == null or session.room == null:
		return false
	if not facing_exit(session, player.global_position, player.facing_yaw()):
		return false
	_bye_said = true
	player.stop_for_door()
	_say_goodbye()
	return true


## True when `pos` is on the row just inside the exit strip and `yaw` points at it.
static func facing_exit(session: IndoorSession, pos: Vector3, yaw: float) -> bool:
	var cell: Vector2i = session.grid.world_to_cell(pos)
	var door: Vector2i = session.room.door_cell
	if cell.y != door.y - 1 or (cell.x != door.x and cell.x != door.x + 1):
		return false
	var target: Vector3 = session.grid.cell_to_world(Vector2i(cell.x, door.y))
	var to: Vector3 = target - pos
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return true
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	return fwd.dot(to.normalized()) > 0.5


func _say_goodbye() -> void:
	var ui := DialogueOverlay.find(get_tree())
	if ui == null:
		_leave_shop()
		return
	_talking = true
	if not ui.closed.is_connected(_on_goodbye_closed):
		ui.closed.connect(_on_goodbye_closed, CONNECT_ONE_SHOT)
	ui.play(_one_line("mabel_bye", NeedleworkTalk.TEXT_BYE), _make_ctx())


func _on_goodbye_closed() -> void:
	_talking = false
	_leave_shop()


func _leave_shop() -> void:
	var host: Node = get_tree().get_first_node_in_group("interior") if get_tree() != null else null
	if host != null and host.has_method("leave_through_exit"):
		host.call("leave_through_exit")
	elif Game != null:
		Game.exit_interior()


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	return [Interaction.of(Interaction.TALK, "Talk to Mabel", 20)]


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.TALK or Game == null:
		return false
	return _begin_talk(ctx)


## Called by an `able_fixture` when the player presses A at a mannequin / umbrella
## stand (decomp `player_buy` sets `buy_ut_idx` → `aNNW_THINK_OMATIKUDASI`, then force
## talk 3 / 4 opens `aNNW_TALK_TRADE_CHECK`). `slot` is the shop display slot.
func begin_trade(slot: int, ctx: InteractionContext) -> bool:
	if Game == null or Game.designs == null:
		return false
	_trade_fixture = slot
	_pending = Pending.NONE
	var listener: Node3D = ctx.actor as Node3D if ctx != null else _player_node()
	_face_toward(listener.global_position if listener != null else global_position)
	_talked_today = true
	_auto_greeted = true
	_flow_trade_menu()
	return true


func _begin_talk(ctx: InteractionContext = null) -> bool:
	## `ctx == null` → Mabel started the talk herself on walk-in
	## (`aNNW_force_talk_request`): a plain welcome line, NO 6-way menu. The menu
	## only opens when the player presses A (`aNNW_norm_talk_request`).
	var listener: Node3D = ctx.actor as Node3D if ctx != null else _player_node()
	_face_toward(listener.global_position if listener != null else global_position)
	_pending = Pending.NONE
	if ctx == null:
		return _auto_greet(listener)
	## `aNNW_set_norm_talk_info`: 0x2FD4 (WHAT_HAPPEN_FIRST) until "What's this?" has
	## been picked once (`needlework_first_talk_flags & 0x40`), 0x3005 after.
	## April Fools' Day's trick instead of the menu (`aNNW_TALK_END_WAIT`).
	var trick: DialogueData = AprilFools.conversation(&"mable")
	if trick != null:
		var ui := DialogueOverlay.find(get_tree())
		if ui != null:
			_start_talk_session(listener)
			_bind_end(ui)
			ui.play(trick, _make_ctx())
		_talked_today = true
		return true
	var lead: String = NeedleworkTalk.TEXT_MENU
	if Game.designs != null and not Game.designs.listened_flag:
		lead = NeedleworkTalk.TEXT_MENU_FIRST
	_play_menu(lead)
	_talked_today = true
	return true


## `aNNW_set_force_talk_info` talk_idx 0 / 1 → msg 0x2FD1 (first ever visit) /
## 0x2FD2 (repeat), then `aNNW_TALK_END_WAIT` — line only, no menu.
func _auto_greet(listener: Node3D) -> bool:
	var first := Game.designs != null and not Game.designs.first_talk_done
	if Game.designs != null:
		Game.designs.first_talk_done = true
	var line := ("Hi there! Come on in.\nWelcome to Able Sisters,\nwhere YOU are the famous\nfashion designer!"
		if first else "Oh, hi! Come on in!")
	var ui := DialogueOverlay.find(get_tree())
	if ui != null:
		_start_talk_session(listener)
		_bind_end(ui)
		ui.play(_one_line("mabel_welcome", line), _make_ctx())
	elif Game != null:
		Game.post_notice("Mabel: %s" % line.replace("\n", " "))
	_talked_today = true
	return true


## The 6-way menu (`aNNW_set_6_ways`) led by `lead`. Options come from `mabel_menu`.
func _play_menu(lead: String) -> void:
	var base: DialogueData = DialogueCatalog.conversation(MENU_ID)
	var ui := DialogueOverlay.find(get_tree())
	if ui == null:
		if Game != null:
			Game.post_notice("Mabel: %s" % lead.replace("\n", " "))
		return
	var menu: Dictionary = {}
	var bye: Dictionary = {}
	if base != null:
		base.ensure_loaded()
		menu = base.node(&"menu").duplicate(true)
		bye = base.node(&"bye").duplicate(true)
	if menu.is_empty():
		_say_line(lead)
		return
	menu["prompt"] = lead
	var nodes := {"lead": {"type": "line", "text": lead, "next": "menu"}, "menu": menu}
	if not bye.is_empty():
		nodes["bye"] = bye
	_start_talk_session(_player_node())
	_bind_session(ui)
	ui.play(DialogueData.from_dict({"id": "mabel_menu_live", "start": "lead", "nodes": nodes}), _make_ctx())


## A result line, then back to the 6-way (`mMsg_Set_continue_msg_num` + WHAT_HAPPEN).
func _line_then_menu(text: String) -> void:
	_line_queue = [{"text": text, "speaker": "Mabel"}]
	_after_queue = Callable(self, "_play_menu").bind(NeedleworkTalk.TEXT_MENU_AGAIN)
	_flush_queue()


func _make_ctx(speaker: String = "Mabel") -> DialogueContext:
	var c: DialogueContext = DialogueContext.from_game()
	c.speaker_name = speaker
	## Special NPCs keep the default green nameplate (`NAME_BG_OTHER`) — same as
	## Tom Nook / Booker / Pelly. Only animal villagers get the pink/blue plate.
	c.voice_mode = DialogueVoice.Mode.ANIMALESE
	c.sound_spec = 4
	## `aNNW_talk_init`: FREE_STR0 / 1 = "Mabel" / "Sable" (strings 0x6D5 / 0x6D6).
	c.frees = PackedStringArray(["Mabel", "Sable"])
	return c


static func _one_line(id: String, text: String) -> DialogueData:
	return DialogueData.from_dict({"id": id, "start": "l", "nodes": {"l": {"type": "line", "text": text}}})


func _bind_session(ui: DialogueOverlay) -> void:
	_active_ui = ui
	if not ui.event_fired.is_connected(_on_dialogue_event):
		ui.event_fired.connect(_on_dialogue_event)
	if ui.closed.is_connected(_on_talk_closed):
		ui.closed.disconnect(_on_talk_closed)
	ui.closed.connect(_on_talk_closed, CONNECT_ONE_SHOT)


func _bind_end(ui: DialogueOverlay) -> void:
	if ui == null or ui.closed.is_connected(_on_talk_closed):
		return
	ui.closed.connect(_on_talk_closed, CONNECT_ONE_SHOT)


func _on_dialogue_event(event: Dictionary) -> void:
	match str(event.get("op", "")):
		"needlework_menu":
			match str(event.get("choice", "")):
				"design": _pending = Pending.DESIGN
				"book": _pending = Pending.BOOK
				"trend": _pending = Pending.TREND
				"listen":
					_pending = Pending.LISTEN
					## `aNNW_first_talk_end(0x40)` on picking "What's this?".
					if Game != null and Game.designs != null:
						Game.designs.listened_flag = true
				"gba": _pending = Pending.GBA
		"needlework_trade":
			_trade_act = str(event.get("act", ""))
			_pending = Pending.TRADE_PICK
		"needlework_act":
			_next_act = str(event.get("act", ""))
			_pending = Pending.ACT


func _on_talk_closed() -> void:
	if _active_ui != null:
		if _active_ui.event_fired.is_connected(_on_dialogue_event):
			_active_ui.event_fired.disconnect(_on_dialogue_event)
	_active_ui = null
	_talking = false
	TalkCamera.end(get_tree())
	var next: Pending = _pending
	_pending = Pending.NONE
	match next:
		Pending.DESIGN: _flow_design_check()
		Pending.BOOK: _flow_save_pattern()
		Pending.TREND: _flow_trend()
		Pending.LISTEN: _flow_whats_this()
		Pending.GBA: _flow_other_things()
		Pending.TRADE_PICK: _flow_trade_pick()
		Pending.ACT: _run_act(_next_act)
		_:
			_trade_fixture = -1
			_trade_act = ""
			_next_act = ""


# --- sub-flows --------------------------------------------------------------

func _play_dialogue(dict: Dictionary) -> void:
	var ui := DialogueOverlay.find(get_tree())
	if ui == null:
		return
	_start_talk_session(_player_node())
	_bind_session(ui)
	ui.play(DialogueData.from_dict(dict), _make_ctx())


## `aNNW_talk_design_check` — msg `0x2FE5`: cost + 8-slot warning, then
## "That's fine!" / "That won't do!" (back to the menu).
func _flow_design_check() -> void:
	_play_dialogue({
		"id": "mabel_design_check", "start": "l0",
		"nodes": {
			"l0": {"type": "line", "text": "Oh, you want to create your\nown design? Great! It'll cost\n350 Bells for materials,\nof course. That's OK, right?", "next": "l1"},
			"l1": {"type": "line", "text": "Oh, and you can only keep\neight designs, so you'll have\nto give up one of the patterns\nyou have now. Is that OK?", "next": "menu"},
			"menu": {"type": "choice", "prompt": "Oh, and you can only keep\neight designs, so you'll have\nto give up one of the patterns\nyou have now. Is that OK?", "options": [
				{"text": "That's fine!", "events": [{"op": "needlework_act", "act": "make_design"}]},
				{"text": "That won't do!", "events": [{"op": "needlework_act", "act": "menu"}]},
			]},
		},
	})


## `aNNW_talk_cporiginal0-2` — msg `0x2FEC`, then the design album
## (`mSM_OVL_NEEDLEWORK` with `mNW_OPEN_CPORIGINAL`). The GC kept it on the Memory
## Card; here it's `DesignBook.album` in the save.
func _flow_save_pattern() -> void:
	## `aNNW_set_6_ways`: a visitor gets 0x2FEE and the menu again.
	if Game.foreigner:
		_line_then_menu(NeedleworkTalk.TEXT_ALBUM_VISITOR)
		return
	_line_queue = [{"text": "OK, then, tell me how you'd\nlike to save it.", "speaker": "Mabel"}]
	_after_queue = Callable(self, "_run_act").bind("open_album")
	_flush_queue()


## `0x2FD6` (`CHECK_LISTEN`) — the "custom designs" pitch + "Any tips?" /
## "I know already.".
func _flow_whats_this() -> void:
	_play_dialogue({
		"id": "mabel_whats_this", "start": "l0",
		"nodes": {
			"l0": {"type": "line", "text": "OK, OK, check this out. Ahem!\nBrand-name clothing is nice,", "next": "l1"},
			"l1": {"type": "line", "text": "but wouldn't you just love to\nwear outfits YOU designed?", "next": "l2"},
			"l2": {"type": "line", "text": "Oh, come on! Admit it!\nI'm sure you've thought the\nsame thing at least once,\nmaybe even twice.", "next": "l3"},
			"l3": {"type": "line", "text": "Well, I know you'll find this\nhard to believe, but the\nAble Sisters can turn your\ndesigning dreams into reality!", "next": "l4"},
			"l4": {"type": "line", "text": "I know, I know, it sounds\ntoo good to be true, huh?\nDon't you just feel the need\nto hear more about it?", "next": "menu"},
			"menu": {"type": "choice", "prompt": "I know, I know, it sounds\ntoo good to be true, huh?\nDon't you just feel the need\nto hear more about it?", "options": [
				{"text": "Any tips?", "events": [{"op": "needlework_act", "act": "listen"}]},
				{"text": "I know already.", "goto": "bye"},
			]},
			"bye": {"type": "line", "text": "Oh, are you sure? OK.\nDon't hesitate to ask if\nthere's anything I can help\nyou with!"},
		},
	})


## `0x2FE2` (`OTHER_HAPPEN`) — the GBA / e-Reader 5-way. Every branch needs a linked
## Game Boy Advance (`aNNW_check_GBA` → NOT_CONNECTED → 0x3008 → menu).
func _flow_other_things() -> void:
	_play_dialogue({
		"id": "mabel_other", "start": "l0",
		"nodes": {
			"l0": {"type": "line", "text": "When you say \"other things,\"\nwhat exactly do you mean?", "next": "menu"},
			"menu": {"type": "choice", "prompt": "When you say \"other things,\"\nwhat exactly do you mean?", "options": [
				{"text": "Download tool", "events": [{"op": "needlework_act", "act": "gba"}]},
				{"text": "Upload design", "events": [{"op": "needlework_act", "act": "gba"}]},
				{"text": "Read card", "events": [{"op": "needlework_act", "act": "gba"}]},
				{"text": "Prep e-Reader", "events": [{"op": "needlework_act", "act": "gba"}]},
				{"text": "Maybe not...", "events": [{"op": "needlework_act", "act": "menu"}]},
			]},
		},
	})


func _run_act(act: String) -> void:
	_next_act = ""
	match act:
		"menu":
			_play_menu(NeedleworkTalk.TEXT_MENU_AGAIN)
		"make_design":
			## `mSP_money_check(aNNW_DESIGN_PRICE)` — sacks count; paid only once the
			## design is saved and named (`aNNW_talk_design_close3`).
			if not ShopBook.can_afford(Game.inventory, NeedleworkTalk.DESIGN_PRICE):
				_line_then_menu(NeedleworkTalk.TEXT_NO_MONEY % _player_name())
				return
			var list_ui: Node = _grp("design_list_ui")
			if list_ui != null and list_ui.has_method("open"):
				list_ui.call("open", "pick_edit", Callable(self, "_on_design_slot_chosen"))
		"open_album":
			var album_ui: Node = _grp("design_album_ui")
			if album_ui != null and album_ui.has_method("open"):
				album_ui.call("open", Callable(self, "_on_album_closed"))
			else:
				_line_then_menu(NeedleworkTalk.TEXT_ALBUM_DONE)
		"listen":
			_flow_listen()
		"gba":
			_line_then_menu(NeedleworkTalk.TEXT_NO_GBA)


func _player_name() -> String:
	if Game != null and Game.player_name != "":
		return Game.player_name
	return "friend"


## `aNNW_talk_design_close`: a slot → the editor; cancelled → 0x2FE9, back to the menu.
func _on_design_slot_chosen(slot: int) -> void:
	if slot < 0:
		_line_then_menu(NeedleworkTalk.TEXT_DESIGN_CANCEL)
		return
	_edit_slot = slot
	var editor: Node = _grp("design_ui")
	if editor != null and editor.has_method("open"):
		editor.call("open", slot, Callable(self, "_on_editor_done"))


## `aNNW_talk_design_close2`: saved → 0x2FEA, then the name entry
## (`aNNW_talk_design_open3`); quit without saving → 0x2FE9, no charge.
func _on_editor_done(slot: int, saved: bool) -> void:
	if not saved or slot < 0 or Game.designs == null:
		_edit_slot = -1
		_line_then_menu(NeedleworkTalk.TEXT_DESIGN_CANCEL)
		return
	_line_queue = [{"text": NeedleworkTalk.TEXT_DESIGN_SAVED, "speaker": "Mabel"}]
	_after_queue = Callable(self, "_open_name_entry")
	_flush_queue()


func _open_name_entry() -> void:
	var d: DesignPattern = Game.designs.player[Game.designs.resolved_index(_edit_slot)]
	var initial: String = d.name if d != null and d.name != "blank" else ""
	var name_ui: Node = _grp("name_entry_ui")
	if name_ui != null and name_ui.has_method("open"):
		name_ui.call("open", initial, Callable(self, "_on_name_entered"))
	else:
		_on_name_entered(initial if initial != "" else "design")


## `aNNW_talk_design_close3`: pay (`mSP_get_sell_price`), store the name, change the
## player's shirt if they're wearing this slot (`CLOTH_CHANGE2`), then 0x2FEB.
func _on_name_entered(text: String) -> void:
	if _edit_slot < 0 or Game.designs == null:
		return
	ShopBook.pay(Game.inventory, NeedleworkTalk.DESIGN_PRICE)
	var d: DesignPattern = Game.designs.player[Game.designs.resolved_index(_edit_slot)]
	if d != null:
		d.name = text
		d.clamp_name()
	Game.designs.changed.emit()
	DesignTexture.clear_cache()
	if Game.worn_design_slot == _edit_slot:
		Game.design_changed.emit()
	_edit_slot = -1
	_line_then_menu(NeedleworkTalk.TEXT_DESIGN_NAMED % text)


## `aNNW_talk_cporiginal2`: 0x2FF0, back to the menu (`CLOTH_CHANGE3` when the worn
## design moved — `design_changed` already re-dressed the player).
func _on_album_closed() -> void:
	_line_then_menu(NeedleworkTalk.TEXT_ALBUM_DONE)


## `aNNW_talk_trend_cloth` — reports the most-worn shirt, then umbrella
## (`aNNW_set_trend_cloth_message` / `_umbrella_message`), then ends.
func _flow_trend() -> void:
	if Game == null or Game.designs == null:
		return
	var cloth: Array = Game.designs.trend_top(false, _rng)
	var umb: Array = Game.designs.trend_top(true, _rng)
	_line_queue = [
		{"text": NeedleworkTalk.trend_line(Game.designs.shop[cloth[0] & 7].name, int(cloth[1]), false), "speaker": "Mabel"},
		{"text": NeedleworkTalk.trend_line(Game.designs.shop[umb[0] & 7].name, int(umb[1]), true), "speaker": "Mabel"},
	]
	_after_queue = Callable()
	_flush_queue()


## `aNNW_talk_listen_sister*` — Mabel explains the shop, the camera takes in both
## sisters (`aNNW_change_camera_priority_demo`), Sable adds a line, and it ends
## (`LISTEN_SISTER4` → END_WAIT). Not the story — that's Sable's own talk.
func _flow_listen() -> void:
	var sable := _sister()
	_line_queue.clear()
	for entry: Array in NeedleworkTalk.LISTEN_LINES:
		_line_queue.append({"text": entry[1], "speaker": entry[0], "focus": sable if entry[0] == "Sable" else null})
	_after_queue = Callable()
	_flush_queue()


## `aNNW_talk_trade_check` — msg `0x2FF2` (cloth) / `0x2FF3` (umbrella), the 4-way
## display menu, then the `GIVE_ADMISSION` confirm sub-step (`0x2FF4` / `0x2FFB`).
func _flow_trade_menu() -> void:
	if _trade_fixture < 0 or Game.designs == null:
		return
	var nm: String = Game.designs.shop[_trade_fixture & 7].name
	var ask := "Yes! Um, sure thing! I like\nto call that design the\n\"%s.\"\nCan I help you with it?" % nm
	var cd := "That means I have to get rid\nof the pattern we have on\ndisplay now, but you're fine\nwith that, right?"
	var cb := "If you end up with more than\neight designs, you have to get\nrid of one. But you're OK\nwith that, right?"
	var data := DialogueData.from_dict({
		"id": "mabel_trade", "start": "start",
		"nodes": {
			"start": {"type": "line", "text": ask, "next": "menu"},
			"menu": {"type": "choice", "prompt": ask, "options": [
				{"text": "Display mine!", "goto": "confirm_display"},
				{"text": "I want it!", "goto": "confirm_buy"},
				{"text": "Can we trade?", "goto": "ask_trade"},
				{"text": "Never mind...", "goto": "bye"},
			]},
			"confirm_display": {"type": "line", "text": cd, "next": "cd_menu"},
			"cd_menu": {"type": "choice", "prompt": cd, "options": [
				{"text": "Sure!", "events": [{"op": "needlework_trade", "act": "display"}]},
				{"text": "I'll trade...", "events": [{"op": "needlework_trade", "act": "exchange"}]},
				{"text": "Never mind...", "goto": "bye"},
			]},
			"confirm_buy": {"type": "line", "text": cb, "next": "cb_menu"},
			"cb_menu": {"type": "choice", "prompt": cb, "options": [
				{"text": "Sure!", "events": [{"op": "needlework_trade", "act": "buy"}]},
				{"text": "I'll trade...", "events": [{"op": "needlework_trade", "act": "exchange"}]},
				{"text": "Never mind...", "goto": "bye"},
			]},
			"ask_trade": {"type": "line", "text": "Oh, OK. Which design would\nyou like to trade it for?",
				"events": [{"op": "needlework_trade", "act": "exchange"}]},
			"bye": {"type": "line", "text": "Oh, I see."},
		},
	})
	var ui := DialogueOverlay.find(get_tree())
	if ui == null:
		_trade_fixture = -1
		return
	_start_talk_session(_player_node())
	_bind_session(ui)
	ui.play(data, _make_ctx())


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
	if fixture < 0 or Game.designs == null:
		return
	if player_slot < 0:
		_say_line(NeedleworkTalk.TEXT_TRADE_CANCEL)
		return
	var affected := Game.designs.resolved_index(player_slot)
	if not apply_trade(Game.designs, act, fixture, player_slot):
		return
	Audio.play_se(&"cursol")
	DesignTexture.clear_cache()
	_say_line(NeedleworkTalk.trade_result_line(act))
	## `org_idx == Now_Private->cloth.idx` → `aNNW_TALK_CLOTH_CHANGE` (not for display).
	if act != "display" and Game.worn_design_slot >= 0 \
			and Game.designs.resolved_index(Game.worn_design_slot) == affected:
		Game.design_changed.emit()


## The three `aNNW_talk_trade_close` cases. Replacing what's on a display (exchange /
## display mine) sends its wearers back to their own clothes (`aNNW_trend_delete_*`);
## taking a copy ("I want it!") leaves the display alone.
static func apply_trade(book: DesignBook, act: String, fixture: int, player_slot: int,
		states: Variant = null) -> bool:
	match act:
		"display":
			book.copy_player_to_shop(fixture, player_slot)
			book.trend_delete(fixture, states)
		"buy":
			book.buy_shop_into_player(fixture, player_slot)
		"exchange":
			book.exchange(fixture, player_slot)
			book.trend_delete(fixture, states)
		_:
			return false
	return true


# --- Sable story support ---------------------------------------------------

## `aNNW_THINK_AINOTE` / `aNNW_ainote_init`: turn to Sable and hold still while she
## tells a story; `null` releases Mabel back to her normal think.
func chime_in(sable: Node3D) -> void:
	_chiming = sable


func _sister() -> Node3D:
	return get_tree().get_first_node_in_group("needlework_sable") as Node3D if get_tree() != null else null


# --- sequential dialogue queue -------------------------------------------

func _flush_queue() -> void:
	if _line_queue.is_empty():
		_finish_queue()
		return
	var entry: Dictionary = _line_queue.pop_front()
	var speaker: String = str(entry.get("speaker", "Mabel"))
	var ui := DialogueOverlay.find(get_tree())
	if ui == null:
		Game.post_notice("%s: %s" % [speaker, str(entry.get("text", "")).replace("\n", " ")])
		_flush_queue()
		return
	var focus: Node3D = entry.get("focus") as Node3D
	if focus != null:
		## `Camera2_request_main_needlework_talk` — frame the two sisters.
		_talking = true
		_chiming = focus
		TalkCamera.begin(self, focus, get_tree(), false)
	else:
		_chiming = null
		_start_talk_session(_player_node())
	if not ui.closed.is_connected(_on_queue_closed):
		ui.closed.connect(_on_queue_closed, CONNECT_ONE_SHOT)
	ui.play(_one_line("mabel_queue", str(entry.get("text", ""))), _make_ctx(speaker))


func _on_queue_closed() -> void:
	_talking = false
	_chiming = null
	if not _line_queue.is_empty():
		_flush_queue()
		return
	_finish_queue()


func _finish_queue() -> void:
	_chiming = null
	var then := _after_queue
	_after_queue = Callable()
	if then.is_valid():
		then.call()
	else:
		_talking = false
		TalkCamera.end(get_tree())


func _grp(g: String) -> Node:
	return get_tree().get_first_node_in_group(g) if get_tree() != null else null


func _player_node() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D if get_tree() != null else null


func _say_line(text: String) -> void:
	_line_queue = [{"text": text, "speaker": "Mabel"}]
	_after_queue = Callable()
	_flush_queue()


func _today() -> String:
	return "%04d-%02d-%02d" % [Clock.year, Clock.month, Clock.day]


# --- boilerplate -----------------------------------------------------------

func _start_talk_session(listener: Node3D) -> void:
	_talking = true
	if listener != null:
		TalkCamera.begin(listener, self, get_tree())
	_play_clip(ANIM_WAIT, true)


func _face_player() -> void:
	var player := Player.find(get_tree())
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
	_body_anim = VisualAnimation.find_animation_player(vis)
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
