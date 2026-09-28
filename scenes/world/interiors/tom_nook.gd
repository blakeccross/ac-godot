extends StaticBody3D

## Tom Nook in Nook's Cranny (`ac_npc_shop_master` / `SP_NPC_RCN_GUIDE2` during first job).

const ANIM_WAIT := "npc_1_wait1"

## Prefer bank ids; authored JSON is the no-bank fallback.
const JOB_ARRIVE := &"msg_2030"
const JOB_ARRIVE_FALLBACK := &"nook_job_arrive"
const JOB_UNIFORM := &"msg_2033"
const JOB_UNIFORM_FALLBACK := &"nook_job_uniform"
const JOB_UNIFORM_WAIT := &"msg_2034"
const JOB_UNIFORM_WAIT_FALLBACK := &"nook_job_uniform_wait"
const JOB_UNIFORM_HINT := &"msg_2035"
const JOB_UNIFORM_HINT_FALLBACK := &"nook_job_uniform_hint"
const JOB_UNIFORM_DONE := &"msg_2036"
const JOB_UNIFORM_DONE_FALLBACK := &"nook_job_uniform_done"
const JOB_PLANT := &"msg_2038"
const JOB_PLANT_FALLBACK := &"nook_job_plant"
const JOB_PLANT_DONE := &"msg_2041"
const JOB_PLANT_DONE_FALLBACK := &"nook_job_plant_done"
const JOB_POCKETS_FULL := &"msg_2032"
const JOB_POCKETS_FULL_FALLBACK := &"nook_job_pockets_full"
const JOB_ALREADY_UNIFORM := &"msg_2103"
const JOB_ALREADY_UNIFORM_FALLBACK := &"nook_job_already_uniform"
const JOB_GOODS_BLOCK := &"msg_2076"
const JOB_GOODS_BLOCK_FALLBACK := &"nook_job_goods_block"
const JOB_INTRO := &"nook_job_intro"
const JOB_INTRO_HINT := &"nook_job_intro_hint"
const JOB_INTRO_DONE := &"nook_job_intro_done"
const JOB_FTR := FirstJob.DIALOGUE_FURNITURE
const JOB_FTR_HINT := FirstJob.DIALOGUE_FURNITURE_HINT
const JOB_FTR_DONE := &"nook_job_furniture_done"
const JOB_LETTER := FirstJob.DIALOGUE_LETTER
const JOB_LETTER_HINT := FirstJob.DIALOGUE_LETTER_HINT
const JOB_LETTER_DONE := &"nook_job_letter_done"
const JOB_OPEN := &"nook_job_open"
const JOB_OPEN_HINT := &"nook_job_open_hint"
const JOB_OPEN_DONE := &"nook_job_open_done"
const JOB_CARPET := FirstJob.DIALOGUE_CARPET
const JOB_CARPET_HINT := FirstJob.DIALOGUE_CARPET_HINT
const JOB_CARPET_DONE := &"nook_job_carpet_done"
const JOB_AXE := FirstJob.DIALOGUE_AXE
const JOB_AXE_HINT := FirstJob.DIALOGUE_AXE_HINT
const JOB_AXE_DONE := &"nook_job_axe_done"
const JOB_NOTICE := &"nook_job_notice"
const JOB_NOTICE_HINT := &"nook_job_notice_hint"
const JOB_ALL_DONE := &"nook_job_all_done"

var _model: Node3D
var _body_anim: AnimationPlayer
var _face: NpcFace = NpcFace.new()
var _talking: bool = false
var _talked_today: bool = false
var _clip: String = ""
var _pending_after: StringName = &""
var _force_greet_queued: bool = false
## Store talk follow-ups: paper to open after the talk (`&"sell"` / `&"order"`) and the
## shirt worn before a try-on (`aNSC_chg_cloth_start_wait`), restored when the talk ends.
var _open_after: StringName = &""
var _try_on_restore: StringName = &""
var _shop_talk: bool = false
## Goodbye said at the exit this visit (`aNSC_goodbye_wait` → `aNSC_exit_wait`).
var _bye_said: bool = false


func _ready() -> void:
	## Not in `shop_set` — restock only clears shelf goods, not the shopkeeper.
	add_to_group("interactable")
	add_to_group("tom_nook")
	collision_layer = 1
	collision_mask = 0
	_ensure_collision()
	_ensure_visual()
	_ensure_interact()
	call_deferred("_maybe_force_greet")


func _process(delta: float) -> void:
	var uttering: bool = false
	if _talking and get_tree() != null:
		uttering = DialogueOverlay.uttering_in(get_tree())
	_face.tick(delta, uttering)
	if _talking:
		_face_player()
	else:
		_check_goodbye()


## Talk only: sell / order / other go through his menu, and goods are bought at the shelf
## (`aNSC_message_ctrl_talk_request_normal_day`).
func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	return [Interaction.of(Interaction.TALK, "Talk to Tom Nook", 20)]


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null or Game == null or action.id != Interaction.TALK:
		return false
	return _begin_talk(ctx)


func _maybe_force_greet() -> void:
	## `aNRG2_think_init` force-talk on first shop visit during FIRSTJOB_START.
	if Game == null:
		return
	if Game.first_job == null or not Game.first_job.is_active():
		## `aNSC_start_wait`: he speaks up on every entry (not on raffle day).
		if Game.shops.is_lottery_day() or _force_greet_queued:
			return
		_force_greet_queued = true
		if get_tree() != null:
			await get_tree().process_frame
			await get_tree().process_frame
		if not is_instance_valid(self) or Player.find(get_tree()) == null:
			return
		_begin_entry_greeting(Player.find(get_tree()))
		return
	if Game.first_job.shop_greeted:
		return
	if _force_greet_queued:
		return
	_force_greet_queued = true
	if get_tree() != null:
		await get_tree().process_frame
		await get_tree().process_frame
	if not is_instance_valid(self):
		return
	var player := Player.find(get_tree())
	var ctx := InteractionContext.new()
	ctx.actor = player
	_begin_talk(ctx)


func _begin_talk(ctx: InteractionContext) -> bool:
	var listener: Node3D = _listener(ctx)
	_face_toward(listener.global_position if listener != null else global_position)
	if Game != null and Game.first_job != null and Game.first_job.is_active():
		return _begin_first_job_talk(listener)
	return _begin_normal_talk(listener)


## Entry greeting (`aNSC_start_wait`, `NookShopTalk.entry_talk`).
func _begin_entry_greeting(listener: Node3D) -> bool:
	var house: House = Game.interiors.player_house() if Game.interiors != null else null
	var talk: Dictionary = NookShopTalk.entry_talk(house, Game.inventory, Game.num_statues)
	var ui := DialogueOverlay.find(get_tree())
	if ui == null or talk.get("data") == null:
		return false
	var talk_ctx: DialogueContext = DialogueContext.from_game()
	talk_ctx.speaker_name = "Tom Nook"
	var house_plan: Dictionary = talk["house"]
	if not house_plan.is_empty():
		NookHouseTalk.fill_context(talk_ctx, house_plan)
		if house_plan.has("statues_built"):
			Game.num_statues = int(house_plan["statues_built"])
		if not ui.event_fired.is_connected(_on_house_event):
			ui.event_fired.connect(_on_house_event)
	_face_toward(listener.global_position if listener != null else global_position)
	if ui.is_open():
		ui.close()
	_start_talk_session(listener)
	_bind_talk_end(ui)
	ui.play(talk["data"] as DialogueData, talk_ctx)
	return true


## A: the counter menu, or the raffle on raffle day (`NookShopTalk.counter_talk`).
func _begin_normal_talk(listener: Node3D) -> bool:
	var talk_ctx: DialogueContext = DialogueContext.from_game()
	talk_ctx.speaker_name = "Tom Nook"
	if Game.shops.is_lottery_day():
		NookShopTalk.fill_lottery(talk_ctx)
	else:
		## `aNSC_check_present_balloon`: a sale-event gift on the first talk.
		var balloon: StringName = Game.shops.take_sale_balloon(Game.inventory)
		NookShopTalk.fill_menu(talk_ctx, _talked_today, balloon)
	_talked_today = true
	return _play_shop_talk(NookShopTalk.counter_talk(), talk_ctx, listener)


## Shop paper picks come back here (`aNSC_msg_win_open_wait`): he names the total and asks.
func quote_sell(item_id: StringName, count: int) -> bool:
	var talk_ctx: DialogueContext = DialogueContext.from_game()
	talk_ctx.speaker_name = "Tom Nook"
	NookShopTalk.fill_sell(talk_ctx, item_id, count)
	return _play_shop_talk(DialogueCatalog.conversation(NookShopTalk.DEAL_ID), talk_ctx, _player())


## Catalog pick (`aNSC_msg_win_open_wait2` → `aNSC_order_check`).
func quote_order(item_id: StringName) -> bool:
	var talk_ctx: DialogueContext = DialogueContext.from_game()
	talk_ctx.speaker_name = "Tom Nook"
	NookShopTalk.fill_order(talk_ctx, item_id)
	return _play_shop_talk(DialogueCatalog.conversation(NookShopTalk.DEAL_ID), talk_ctx, _player())


func _play_shop_talk(data: DialogueData, talk_ctx: DialogueContext, listener: Node3D) -> bool:
	var ui := DialogueOverlay.find(get_tree()) if get_tree() != null else null
	if ui == null or data == null:
		return false
	_face_toward(listener.global_position if listener != null else global_position)
	if ui.is_open():
		ui.close()
	_shop_talk = true
	_start_talk_session(listener)
	_bind_talk_end(ui)
	if not ui.event_fired.is_connected(_on_shop_event):
		ui.event_fired.connect(_on_shop_event)
	ui.play(data, talk_ctx)
	return true


func _begin_first_job_talk(listener: Node3D) -> bool:
	var job: FirstJob = Game.first_job
	_pending_after = &""
	_refresh_passive_progress(job)

	if not job.shop_greeted and job.kind == FirstJob.Kind.START:
		job.shop_greeted = true
		if job.wearing_uniform(Game.cloth_id):
			_pending_after = &"start_plant_from_uniform"
			return _play_job_line(JOB_ALREADY_UNIFORM, JOB_ALREADY_UNIFORM_FALLBACK, null, listener)
		if not job.can_start_change_cloth(Game.inventory):
			return _play_job_line(JOB_POCKETS_FULL, JOB_POCKETS_FULL_FALLBACK, null, listener)
		_pending_after = &"give_uniform"
		return _play_job_chain(
			[JOB_ARRIVE, JOB_UNIFORM],
			[JOB_ARRIVE_FALLBACK, JOB_UNIFORM_FALLBACK],
			listener
		)

	job.shop_greeted = true

	if job.chore_finished():
		_pending_after = &"advance"
		return _play_job_line(_done_bank_for(job.kind), _done_fallback_for(job.kind), null, listener)

	match job.kind:
		FirstJob.Kind.CHANGE_CLOTH:
			if Game.inventory.count_of(FirstJob.UNIFORM_ID) > 0:
				return _play_job_line(JOB_UNIFORM_HINT, JOB_UNIFORM_HINT_FALLBACK, null, listener)
			if job.can_start_change_cloth(Game.inventory):
				job.give_uniform(Game.inventory)
				return _play_job_line(JOB_UNIFORM, JOB_UNIFORM_FALLBACK, null, listener)
			return _play_job_line(JOB_POCKETS_FULL, JOB_POCKETS_FULL_FALLBACK, null, listener)
		FirstJob.Kind.PLANT_FLOWER:
			return _play_job_line(JOB_PLANT, JOB_PLANT_FALLBACK, null, listener)
		FirstJob.Kind.INTRODUCTIONS:
			return _play_job_line(&"", JOB_INTRO_HINT, null, listener)
		FirstJob.Kind.DELIVER_FTR:
			return _play_job_line(&"", JOB_FTR_HINT, null, listener)
		FirstJob.Kind.SEND_LETTER, FirstJob.Kind.SEND_LETTER2:
			if Game.inventory.count_of(FirstJob.PAPER_ID) <= 0 and job.can_start_delivery(Game.inventory):
				job.give_paper(Game.inventory)
			return _play_job_line(&"", JOB_LETTER_HINT, null, listener)
		FirstJob.Kind.OPEN:
			return _play_job_line(&"", JOB_OPEN_HINT, null, listener)
		FirstJob.Kind.DELIVER_CARPET:
			return _play_job_line(&"", JOB_CARPET_HINT, null, listener)
		FirstJob.Kind.DELIVER_AXE, FirstJob.Kind.DELIVER_AXE2:
			return _play_job_line(&"", JOB_AXE_HINT, null, listener)
		FirstJob.Kind.POST_NOTICE:
			return _play_job_line(&"", JOB_NOTICE_HINT, null, listener)
		FirstJob.Kind.START:
			if job.wearing_uniform(Game.cloth_id):
				_pending_after = &"start_plant_from_uniform"
				return _play_job_line(JOB_ALREADY_UNIFORM, JOB_ALREADY_UNIFORM_FALLBACK, null, listener)
			if not job.can_start_change_cloth(Game.inventory):
				return _play_job_line(JOB_POCKETS_FULL, JOB_POCKETS_FULL_FALLBACK, null, listener)
			_pending_after = &"give_uniform"
			return _play_job_line(JOB_UNIFORM, JOB_UNIFORM_FALLBACK, null, listener)
		_:
			return _begin_normal_talk(listener)


func _refresh_passive_progress(job: FirstJob) -> void:
	if job.plant_job_finished(Game.inventory):
		job.mark_plant_finished()
	if job.kind == FirstJob.Kind.INTRODUCTIONS:
		job.refresh_introductions()


func _done_bank_for(kind: FirstJob.Kind) -> StringName:
	match kind:
		FirstJob.Kind.CHANGE_CLOTH:
			return JOB_UNIFORM_DONE
		FirstJob.Kind.PLANT_FLOWER:
			return JOB_PLANT_DONE
		_:
			return &""


func _done_fallback_for(kind: FirstJob.Kind) -> StringName:
	match kind:
		FirstJob.Kind.CHANGE_CLOTH:
			return JOB_UNIFORM_DONE_FALLBACK
		FirstJob.Kind.PLANT_FLOWER:
			return JOB_PLANT_DONE_FALLBACK
		FirstJob.Kind.INTRODUCTIONS:
			return JOB_INTRO_DONE
		FirstJob.Kind.DELIVER_FTR:
			return JOB_FTR_DONE
		FirstJob.Kind.SEND_LETTER, FirstJob.Kind.SEND_LETTER2:
			return JOB_LETTER_DONE
		FirstJob.Kind.OPEN:
			return JOB_OPEN_DONE
		FirstJob.Kind.DELIVER_CARPET:
			return JOB_CARPET_DONE
		FirstJob.Kind.DELIVER_AXE, FirstJob.Kind.DELIVER_AXE2:
			return JOB_AXE_DONE
		FirstJob.Kind.POST_NOTICE:
			return JOB_ALL_DONE
		_:
			return JOB_PLANT_DONE_FALLBACK


func _assign_fallback_for(kind: FirstJob.Kind) -> StringName:
	match kind:
		FirstJob.Kind.PLANT_FLOWER:
			return JOB_PLANT_FALLBACK
		FirstJob.Kind.INTRODUCTIONS:
			return JOB_INTRO
		FirstJob.Kind.DELIVER_FTR:
			return JOB_FTR
		FirstJob.Kind.SEND_LETTER, FirstJob.Kind.SEND_LETTER2:
			return JOB_LETTER
		FirstJob.Kind.OPEN:
			return JOB_OPEN
		FirstJob.Kind.DELIVER_CARPET:
			return JOB_CARPET
		FirstJob.Kind.DELIVER_AXE, FirstJob.Kind.DELIVER_AXE2:
			return JOB_AXE
		FirstJob.Kind.POST_NOTICE:
			return JOB_NOTICE
		_:
			return &""


func _play_job_chain(
	ids: Array[StringName],
	fallbacks: Array[StringName],
	listener: Node3D
) -> bool:
	for i: int in ids.size():
		var id: StringName = ids[i]
		var fb: StringName = fallbacks[i] if i < fallbacks.size() else &""
		var data: DialogueData = DialogueCatalog.conversation(id)
		if data == null and fb != &"":
			data = DialogueCatalog.conversation(fb)
			id = fb
		if data == null:
			continue
		if i == 0 and ids.size() > 1:
			if id == JOB_ARRIVE or id == JOB_ARRIVE_FALLBACK:
				_pending_after = &"after_arrive"
				return _play_data(data, listener)
		return _play_data(data, listener)
	return _play_job_line(&"", JOB_ARRIVE_FALLBACK, null, listener)


func _play_job_line(
	id: StringName,
	fallback: StringName,
	_ctx: InteractionContext = null,
	listener: Node3D = null
) -> bool:
	var data: DialogueData = null
	if id != &"":
		data = DialogueCatalog.conversation(id)
	if data == null and fallback != &"":
		data = DialogueCatalog.conversation(fallback)
	if data == null:
		Game.post_notice("Tom Nook: Yes, yes!")
		_apply_pending_after()
		return true
	return _play_data(data, listener)


func _play_data(data: DialogueData, listener: Node3D) -> bool:
	var talk_ctx: DialogueContext = DialogueContext.from_game()
	talk_ctx.speaker_name = "Tom Nook"
	var play_data: DialogueData = data
	if (
		Game != null
		and Game.first_job != null
		and Game.first_job.needs_named_recipient()
		and play_data != null
		and play_data.id in FirstJob.recipient_dialogue_ids()
	):
		if Game.first_job.recipient_id == &"":
			push_error("FirstJob: playing recipient dialogue with empty recipient_id")
		play_data = FirstJob.ensure_dialogue_names_recipient(play_data)
	var ui := DialogueOverlay.find(get_tree())
	if ui != null:
		if ui.is_open():
			ui.close()
		_start_talk_session(listener)
		_bind_talk_end(ui)
		ui.play(play_data, talk_ctx)
		return true
	_apply_pending_after()
	return true


func _start_talk_session(listener: Node3D) -> void:
	_talking = true
	if listener != null:
		TalkCamera.begin(listener, self, get_tree())
	_play_clip(ANIM_WAIT, true)


func _bind_talk_end(ui: DialogueOverlay) -> void:
	if ui == null:
		return
	if ui.closed.is_connected(_on_talk_closed):
		return
	ui.closed.connect(_on_talk_closed, CONNECT_ONE_SHOT)


func _on_house_event(event: Dictionary) -> void:
	var house: House = Game.interiors.player_house() if Game.interiors != null else null
	var notice: String = NookHouseTalk.apply_event(event, house)
	if notice != "":
		Game.post_notice(notice)


## A shelf good was picked (`aNSC_message_ctrl_talk_request_normal_day`): Nook names the
## price and asks. Returns false when there is no dialogue to run it.
func offer_item(item_id: StringName, ctx: InteractionContext) -> bool:
	if Game == null or DialogueOverlay.find(get_tree()) == null:
		return false
	## Goods stay locked during chores (`aNRG2_goods_talk`).
	if Game.first_job != null and Game.first_job.is_active():
		return _play_job_line(JOB_GOODS_BLOCK, JOB_GOODS_BLOCK_FALLBACK, null, _listener(ctx))
	## Past closing (or renovating) the shelf is shut; the door hours rule (`mSP_ShopOpen`).
	if not Game.shops.nook_is_open():
		Game.post_notice(Game.shops.closed_notice())
		return true
	var talk_ctx: DialogueContext = DialogueContext.from_game()
	talk_ctx.speaker_name = "Tom Nook"
	NookShopTalk.fill_offer(talk_ctx, item_id)
	return _play_shop_talk(NookShopTalk.shelf_talk(), talk_ctx, _listener(ctx))


## `aNSC_message_ctrl`: the player faces the exit (`EXIT_DOOR1`) → `aNSC_goodbye_wait` →
## `aNSC_say_goodbye` (normal camera) → `aNSC_exit_wait` leaves the shop. Chores Nook just
## lets them out (`aNRG2_exit_check`).
func _check_goodbye() -> bool:
	if _bye_said or Game == null or Game.block_auto_enter_doors or get_tree() == null:
		return false
	if Game.first_job != null and Game.first_job.is_active():
		return false
	var dlg := DialogueOverlay.find(get_tree())
	if dlg != null and dlg.is_open():
		return false
	var paper: Node = get_tree().get_first_node_in_group("shop_ui")
	if paper != null and paper.has_method("is_open") and bool(paper.call("is_open")):
		return false
	var player := Player.find(get_tree())
	if player == null or player.is_busy():
		return false
	var session: IndoorSession = Game.interior_session
	if session == null or not session.facing_exit(player.global_position, player.facing_yaw()):
		return false
	_bye_said = true
	player.stop_for_door()
	_say_goodbye(dlg)
	return true


func _say_goodbye(ui: DialogueOverlay) -> void:
	var data: DialogueData = NookShopTalk.line(NookShopTalk.GOODBYE_BANK, NookShopTalk.GOODBYE_ID)
	if ui == null or data == null:
		_leave_shop()
		return
	_talking = true
	var talk_ctx: DialogueContext = DialogueContext.from_game()
	talk_ctx.speaker_name = "Tom Nook"
	if not ui.closed.is_connected(_on_goodbye_closed):
		ui.closed.connect(_on_goodbye_closed, CONNECT_ONE_SHOT)
	ui.play(data, talk_ctx)


func _on_goodbye_closed() -> void:
	_talking = false
	_leave_shop()


func _leave_shop() -> void:
	var host: Node = get_tree().get_first_node_in_group("interior") if get_tree() != null else null
	if host != null and host.has_method("leave_through_exit"):
		host.call("leave_through_exit")
	elif Game != null:
		Game.exit_interior()


func _on_shop_event(event: Dictionary) -> void:
	var ui := DialogueOverlay.find(get_tree())
	var ctx: DialogueContext = ui.runner().context if ui != null and ui.runner() != null else null
	var res: Dictionary = NookShopTalk.apply_event(event, ctx)
	if res.get("open", &"") != &"":
		_open_after = res["open"] as StringName
	var try_on: StringName = res.get("try_on", &"") as StringName
	if try_on != &"":
		if _try_on_restore == &"":
			_try_on_restore = Game.cloth_id
		Game.set_cloth(try_on)
	if bool(res.get("bought", false)):
		Game.call_deferred("refresh_shop_set")
	var notice: String = str(res.get("notice", ""))
	if notice != "":
		Game.post_notice(notice)


func _on_talk_closed() -> void:
	_talking = false
	var ui := DialogueOverlay.find(get_tree())
	if ui != null and ui.event_fired.is_connected(_on_house_event):
		ui.event_fired.disconnect(_on_house_event)
	if ui != null and ui.event_fired.is_connected(_on_shop_event):
		ui.event_fired.disconnect(_on_shop_event)
	_shop_talk = false
	## The try-on is a preview: the player changes back either way (`aNSC_sell_check`).
	if _try_on_restore != &"":
		Game.set_cloth(_try_on_restore)
		_try_on_restore = &""
	TalkCamera.end(get_tree())
	if _open_after != &"":
		var mode: StringName = Interaction.SELL if _open_after == &"sell" else ShopUse.ORDER
		_open_after = &""
		Game.open_shop(ShopBook.NOOK_ID, mode)
	await _apply_pending_after()


func _apply_pending_after() -> void:
	var op: StringName = _pending_after
	_pending_after = &""
	if op == &"" or Game == null or Game.first_job == null:
		return
	var job: FirstJob = Game.first_job
	var listener: Node3D = (
		get_tree().get_first_node_in_group("player") as Node3D if get_tree() != null else null
	)
	match op:
		&"after_arrive":
			_pending_after = &"give_uniform"
			_play_job_line(JOB_UNIFORM, JOB_UNIFORM_FALLBACK, null, listener)
		&"give_uniform":
			job.setup_change_cloth()
			await _hand_over_gift(listener, FirstJob.UNIFORM_ID)
			job.give_uniform(Game.inventory)
			Game.set_interact_prompt(job.prompt_for_kind())
			_play_job_line(JOB_UNIFORM_WAIT, JOB_UNIFORM_WAIT_FALLBACK, null, listener)
		&"start_plant_from_uniform":
			job.setup_change_cloth()
			job.tick_cloth(Game.cloth_id)
			if not job.advance_after_finished(Game.inventory):
				_play_job_line(JOB_POCKETS_FULL, JOB_POCKETS_FULL_FALLBACK, null, listener)
				return
			await _hand_over_gift(listener, job.gift_display_item())
			Game.set_interact_prompt(job.prompt_for_kind())
			_play_job_line(JOB_PLANT, JOB_PLANT_FALLBACK, null, listener)
		&"advance":
			if not job.advance_after_finished(Game.inventory):
				_play_job_line(JOB_POCKETS_FULL, JOB_POCKETS_FULL_FALLBACK, null, listener)
				return
			if not job.is_active():
				Game.set_interact_prompt("")
				return
			var gift: StringName = job.gift_display_item()
			if gift != &"":
				await _hand_over_gift(listener, gift)
			Game.set_interact_prompt(job.prompt_for_kind())
			var assign: StringName = _assign_fallback_for(job.kind)
			if assign != &"":
				_play_job_line(&"", assign, null, listener)


func _hand_over_gift(listener: Node3D, item_id: StringName) -> void:
	## `aNRG2_demo_start_wait` → NPC TRANSFER / player GET (`handOverItem`).
	if listener == null:
		return
	await HandOver.npc_gives_to_player(self, listener, item_id)


func play_wait_anim() -> void:
	_play_clip(ANIM_WAIT, true)


func animation_player() -> AnimationPlayer:
	return _body_anim


func _listener(ctx: InteractionContext) -> Node3D:
	return ctx.actor as Node3D if ctx != null else null


func _player() -> Node3D:
	return Player.find(get_tree()) as Node3D if get_tree() != null else null


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
	var species: StringName = ShopDisplay.nook_species(_nook_level())
	var vis: Node3D = GeneratedVisual.attach_villager(_model, species)
	if vis == null:
		var mesh := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.35
		capsule.height = 1.4
		mesh.mesh = capsule
		mesh.position.y = 0.9
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.72, 0.52, 0.28)
		mesh.material_override = mat
		_model.add_child(mesh)
		return
	## Permanent shop master leaves `cloth_idx` NONE (`aNPC_actor_init_for_special`).
	_body_anim = VisualAnimation.find_animation_player(vis)
	_face.bind(vis, species)
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


func _nook_level() -> int:
	if Game != null and Game.current_room_id != &"":
		if ShopDisplay.nook_is_shop_room(Game.current_room_id) or Game.current_room_id == &"shop3_2":
			return ShopDisplay.nook_level_for_room(Game.current_room_id)
	if Game != null and Game.shops != null:
		return Game.shops.nook_level()
	return 0


func _resolve_clip(suffix: String) -> String:
	if _body_anim == null or suffix.is_empty():
		return ""
	if _body_anim.has_animation(suffix):
		return suffix
	for anim_name: String in _body_anim.get_animation_list():
		if anim_name.ends_with(suffix) or suffix in anim_name:
			return anim_name
	return ""
