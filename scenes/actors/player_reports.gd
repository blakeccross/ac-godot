class_name PlayerReports
extends Node

## The player's own reports: holding something up while a report window says what it is, under
## its jingle, with the camera closed in (`mDemo_TYPE_REPORT`, `Camera2_request_main_item`).
## The golden tools, a catch (and the pockets-full swap), a find dug up, the loan paid off and
## the axe giving out. A child of the `Player`; it reads the player's motor, body animation
## and busy flag directly.

## `notice_rod`: the fish page finished (0x134A) under its own jingle (0x4C).
const ROD_COMPLETE_MSG := 0x134A
const ROD_COMPLETE_FANFARE := 0x4C
const POCKETS_FULL_MSG := 4936


## The Player this belongs to (the parent), found on first use: tests build scenes
## without adding them to the tree.
var _player: Player:
	get:
		if _player == null:
			_player = get_parent() as Player
		return _player


## `mPlayer_INDEX_DEMO_GET_GOLDEN_ITEM(2)`: the golden tool held up in the hand with
## `YATTA1`, turning to face the camera, and 42 frames in the player's own green report
## ("YESSSSS!!!!! I got the Golden Rod!", 0x306D–0x306F); then back to waiting with the
## equipped tool again. Tortimer's golden rod / net visit and the well spirit's axe end here.
const GOLDEN_YATTA := &"ply_1_yatta1"
const GOLDEN_REPORT_SEC := 42.0 * DecompTime.FRAME_SEC
const GOLDEN_WINDOW := Color8(185, 245, 80)
const GOLDEN_MSG: Dictionary = {&"golden_net": 0x306D, &"golden_fishing_rod": 0x306E, &"golden_axe": 0x306F}
## `Player_actor_sound_Get_bgm_num_forDemoGetGoldenItem`: `BGM_ALL_INSECTS`, `BGM_ALL_FISH`,
## `BGM_INTRO_CHORES_COMPLETE`, else `BGM_DEBT_PAID`.
const GOLDEN_FANFARE: Dictionary = {&"golden_net": 0x4B, &"golden_fishing_rod": 0x4C, &"golden_axe": 0x49}
const GOLDEN_FANFARE_OTHER := 0x4A


## `mDemo_TYPE_REPORT` → `Camera2_request_main_item`: while the player's own report is up
## the camera closes in on them; when it is dismissed the normal camera eases back.
func report_camera(on: bool) -> void:
	var cam: FollowCamera = FollowCamera.find(get_tree()) if is_inside_tree() else null
	if cam == null:
		return
	if on:
		cam.begin_item(_player)
	else:
		cam.end_item()


func get_golden_item(item_id: StringName) -> void:
	if _player._busy or not is_inside_tree():
		return
	_player._busy = true
	var skeleton: Skeleton3D = HeldTool.find_skeleton(_player._mesh)
	var tool := ItemCatalog.get_item(item_id) as ToolData
	HeldTool.unbind(skeleton)
	if tool != null and tool.visual_id != &"":
		HeldTool.bind(skeleton, tool.visual_id)
		## Only the net has a clip of its own for this (`yatta_m1`); other tools just stay put.
		HeldTool.play(skeleton, Netting.TOOL_YATTA, false)
	_player._play_body_once(GOLDEN_YATTA)
	var jingle: StringName = BgmCatalog.id_for_num(int(GOLDEN_FANFARE.get(item_id, GOLDEN_FANFARE_OTHER)))
	Audio.push_fanfare(jingle)
	var elapsed: float = 0.0
	while elapsed < GOLDEN_REPORT_SEC and is_inside_tree():
		await get_tree().physics_frame
		var delta: float = get_physics_process_delta_time()
		elapsed += delta
		## The turn steps once per 30 fps frame here: half the rate of the tick-stepped turns.
		_player._motor.facing = PlayerLocomotion.ease_turn(_player._motor.facing, Netting.SHOW_YAW, delta * 0.5)
		_player._mesh.rotation.y = _player._motor.facing
	var ui: DialogueOverlay = DialogueOverlay.find(get_tree()) if is_inside_tree() else null
	var data: DialogueData = DialogueCatalog.conversation(StringName("msg_%d" % int(GOLDEN_MSG.get(item_id, 0x3070))))
	if ui != null and data != null:
		var ctx := DialogueContext.from_game()
		ctx.speaker_name = ""
		ctx.window_color = GOLDEN_WINDOW
		report_camera(true)
		ui.play(data, ctx)
		await wait_closed(ui)
		report_camera(false)
	Audio.pop_fanfare(jingle)
	if not is_inside_tree():
		return
	_player._motor.reset(_player._motor.facing)
	_player._motor.mode_changed = true
	_player.tools.bind_equipped_tool(not _player.tools.tool_hidden())
	_player._busy = false
	_player._gait = PlayerLocomotion.Gait.WAIT
	_player._update_focus()


## `mPlayer_INDEX_BROKEN_AXE`: the axe gave out on the last swing. `AXE_BREAK1`, then
## `AXE_BREAKWAIT1`; 80 frames on the report (0x3067) opens in its lilac window. The
## halves fly off at frame 15 (`BrokenAxePiece`).
func broken_axe() -> void:
	while _player._busy and is_inside_tree():
		await get_tree().physics_frame
	if not is_inside_tree():
		return
	_player._busy = true
	HeldTool.unbind(HeldTool.find_skeleton(_player._mesh))
	## The halves fly on the clip's own `fx_axe_pieces` event; `AXE_BREAKWAIT1` follows it.
	_player._play_body_once(AxeWear.ANIM_BREAK)
	var then_wait := func(clip: StringName) -> void:
		if String(clip).ends_with(String(AxeWear.ANIM_BREAK)):
			_player._play_body_loop(AxeWear.ANIM_BREAK_WAIT)
	if _player._anim != null:
		_player._anim.animation_finished.connect(then_wait, CONNECT_ONE_SHOT)
	await get_tree().create_timer(AxeWear.REPORT_DELAY_FRAMES * DecompTime.FRAME_SEC, false).timeout
	if _player._anim != null and _player._anim.animation_finished.is_connected(then_wait):
		_player._anim.animation_finished.disconnect(then_wait)
	if not is_inside_tree():
		return
	var ui: DialogueOverlay = DialogueOverlay.find(get_tree()) if is_inside_tree() else null
	var data: DialogueData = DialogueCatalog.conversation(StringName("msg_%d" % AxeWear.MSG_BROKEN))
	if ui != null and data != null:
		var ctx := DialogueContext.from_game()
		ctx.speaker_name = ""
		ctx.window_color = AxeWear.BROKEN_WINDOW
		report_camera(true)
		ui.play(data, ctx)
		await wait_closed(ui)
		report_camera(false)
	if not is_inside_tree():
		return
	_player._motor.reset(_player._motor.facing)
	_player._motor.mode_changed = true
	_player.tools.bind_equipped_tool(not _player.tools.tool_hidden())
	_player._busy = false
	_player._gait = PlayerLocomotion.Gait.WAIT
	_player._update_focus()


## Opens one catch-report message (`mDemo_Set_msg_num`); 0xA4E names the insect.
func say_net_catch(ui: DialogueOverlay, msg: int, bug: BugData) -> void:
	var data: DialogueData = DialogueCatalog.conversation(StringName("msg_%d" % msg))
	var text: String = BugCatalog.catch_text(msg)
	if ui == null:
		Game.post_notice(text)
		return
	if data != null:
		var ctx := DialogueContext.from_game()
		ctx.item0 = bug.display_name if bug != null else ""
		ui.play(data, ctx)
	else:
		ui.say(text)


func wait_closed(ui: DialogueOverlay) -> void:
	if ui != null and ui.is_open():
		await ui.closed


## `Player_actor_MessageControl_Notice_rod` opens the catch report once its 42 frames are up
## and holds `LockContinue` until the player advances it, so the pose stays on screen for as
## long as the text does. `_update_animation` bails while `_player._busy`, which is what keeps the
## last frame of `GET_T2` up rather than falling back to the idle.
## The text is the game's own: `Player_actor_Get_sakana_msg_num` gives a message number per
## species and the extracted bank has the line, pun and all. The rare three (stringfish,
## coelacanth, arapaima) run to two pages, which is why this plays a conversation through the
## runner instead of pushing a single string.
func report_catch(
	catch_msg: int, pockets_full: bool = false, fish: FishData = null, completes_record: bool = false
) -> void:
	if catch_msg == 0:
		return
	var ui := DialogueOverlay.find(get_tree())
	var data: DialogueData = DialogueCatalog.conversation(StringName("msg_%d" % catch_msg))
	var fallback: String = FishCatalog.catch_text(catch_msg)
	if ui == null:
		Game.post_notice(fallback)
		return
	## 0x1349 names the fish (`mMsg_Set_item_str_art(win, mMsg_ITEM_STR0, …)`).
	var ctx := DialogueContext.from_game()
	ctx.item0 = fish.display_name if fish != null else ""
	report_camera(true)
	if data != null:
		ui.play(data, ctx)
	else:
		ui.say(fallback)
	## `Player_actor_Notice_rod_demo_ct` → `settle_main_Notice_rod`: the catch jingle runs
	## under the report.
	var jingle: StringName = BgmCatalog.id_for_num(Netting.FANFARE_CATCH)
	Audio.push_fanfare(jingle)
	await ui.closed
	## `MessageControl_Notice_rod` states 1–2: the last fish of the page — "I've caught
	## them all!", then `YATTA2` as the jingle turns to the collection-complete one (0x4C).
	if completes_record:
		var all: DialogueData = DialogueCatalog.conversation(StringName("msg_%d" % ROD_COMPLETE_MSG))
		if all != null:
			ui.play(all, ctx)
		else:
			ui.say(FishCatalog.catch_text(ROD_COMPLETE_MSG))
		await ui.closed
		_player._play_body_once(Netting.ANIM_YATTA)
		Audio.pop_fanfare(jingle)
		jingle = BgmCatalog.id_for_num(ROD_COMPLETE_FANFARE)
		Audio.push_fanfare(jingle)
	if pockets_full:
		## "Swap" trades a pocket for the fish (`putaway_rod` → `mSM_IV_OPEN_EXCHANGE`).
		if await ask_swap(POCKETS_FULL_MSG) and fish != null:
			await exchange_into_pockets(fish.id)
	report_camera(false)
	Audio.pop_fanfare(jingle)


## A pockets-full question (Swap / let it go); true when "Swap" was taken.
func ask_swap(msg_no: int) -> bool:
	var ui := DialogueOverlay.find(get_tree())
	var data: DialogueData = DialogueCatalog.conversation(StringName("msg_%d" % msg_no))
	if ui == null or data == null:
		return false
	var talk := BankTalk.Fixed.new(msg_no)
	var dctx := DialogueContext.from_game()
	dctx.speaker_name = ""
	talk.context = dctx
	ui.play(data, dctx, null, Callable(), talk)
	await ui.closed
	return talk.chosen == 0


## `mSM_IV_OPEN_EXCHANGE`: the pockets open, and the one picked goes on the ground in front
## to make room for `item_id`. False when nothing was picked or there's nowhere to put it.
func exchange_into_pockets(item_id: StringName) -> bool:
	var inv: Inventory = Game.inventory
	var data: ItemData = ItemCatalog.get_item(item_id)
	var world := World.find(get_tree())
	if inv == null or data == null or world == null or not (world.grid is WorldGrid):
		return false
	Game.pocket_requests.request_handover(-1, "take")
	var picked: Array = await Game.pocket_requests.handover_resolved
	var pocket: int = int(picked[1])
	var slot: InventorySlot = inv.slot_at(pocket) if pocket >= 0 else null
	if slot == null or slot.is_empty() or slot.item.count > 1:
		return false
	var grid: WorldGrid = world.grid
	var front: Vector2i = ToolUse.facing_cell(_player._make_context())
	var cell: Vector2i = FieldItems.drop_cell(grid, front, front - grid.world_to_cell(_player.global_position))
	if cell.x < 0:
		return false
	var out: InventoryItem = inv.remove_from_slot(pocket, 1)
	inv.add(data, 1)
	FieldItems.put(world, cell, out.item_id, out.condition == InventoryItem.Condition.PRESENT)
	return true


## `COMPLETE_PAYMENT`: `YATTA1` facing the camera under the debt-paid (or chores-done) jingle,
## then "YESSSSS!!!" once 42 ticks are up.
const PAYMENT_MSG_HOUSE := 0x17B7
const PAYMENT_MSG_ARBEIT := 0x17B6
const PAYMENT_FANFARE_HOUSE := 0x4A
const PAYMENT_FANFARE_ARBEIT := 0x49
const PAYMENT_REPORT_SEC := 42.0 * DecompTime.TICK_SEC


func run_complete_payment() -> void:
	var kind: StringName = Game.complete_payment
	if kind == &"" or _player._busy:
		return
	Game.complete_payment = &""
	_player._busy = true
	_player._motor.facing = Netting.SHOW_YAW
	_player._mesh.rotation.y = Netting.SHOW_YAW
	_player._start_one_shot(GOLDEN_YATTA)
	var arbeit: bool = kind == Game.PAYMENT_ARBEIT
	var jingle: StringName = BgmCatalog.id_for_num(PAYMENT_FANFARE_ARBEIT if arbeit else PAYMENT_FANFARE_HOUSE)
	Audio.push_fanfare(jingle)
	await get_tree().create_timer(PAYMENT_REPORT_SEC).timeout
	var ui := DialogueOverlay.find(get_tree())
	var data: DialogueData = DialogueCatalog.conversation(
		StringName("msg_%d" % (PAYMENT_MSG_ARBEIT if arbeit else PAYMENT_MSG_HOUSE)))
	if ui != null and data != null:
		var dctx := DialogueContext.from_game()
		dctx.speaker_name = ""
		dctx.window_color = GOLDEN_WINDOW
		report_camera(true)
		ui.play(data, dctx)
		await ui.closed
		report_camera(false)
	Audio.pop_fanfare(jingle)
	_player._busy = false


## `GET_SCOOP` (`m_player_main_get_scoop`): the find comes up in the hand (`GET_D1`), the
## report and its jingle follow 86 ticks later, then `PUTAWAY_SCOOP`. Pockets full: "Swap"
## opens the pockets (`mSM_IV_OPEN_EXCHANGE`) and the pocket picked goes into the hole for
## it; otherwise the find goes back in (`PUTIN_SCOOP`).
func run_dig_get(item_id: StringName, banked: bool, cell: Vector2i, ctx: InteractionContext) -> void:
	_player._busy = true
	_player._start_one_shot(DigReport.ANIM_GET)
	var prop: HandOverItem = HandOverItem.spawn(_player.get_parent(), item_id)
	if prop != null:
		prop.set_master(_player)
		prop.begin_mode(HandOverItem.Mode.TRANS_WAIT)
	await get_tree().create_timer(DigReport.REPORT_TICKS * DecompTime.TICK_SEC).timeout
	var talk := DigReport.new(item_id, banked)
	var ui := DialogueOverlay.find(get_tree())
	var jingle: StringName = BgmCatalog.id_for_num(DigReport.FANFARE)
	var data: DialogueData = DialogueCatalog.conversation(StringName("msg_%d" % DigReport.MSG_GOT))
	if ui != null and data != null:
		var dctx := DialogueContext.from_game()
		dctx.speaker_name = ""
		dctx.window_color = GOLDEN_WINDOW
		talk.context = dctx
		talk.prepare()
		Audio.push_fanfare(jingle)
		report_camera(true)
		ui.play(data, dctx, null, Callable(), talk)
		await ui.closed
		report_camera(false)
		Audio.pop_fanfare(jingle)
	if prop != null and is_instance_valid(prop):
		prop.finish()
	if not banked:
		await _dig_swap_or_bury(item_id, talk.swap, cell, ctx)
	_player._busy = false


## `PUTAWAY_SCOOP` with `submenu_flag` → the exchange pockets, or `PUTIN_SCOOP` with the find.
func _dig_swap_or_bury(item_id: StringName, swap: bool, cell: Vector2i, ctx: InteractionContext) -> void:
	if swap and Game.inventory != null:
		Game.pocket_requests.request_handover(-1, "take")
		var picked: Array = await Game.pocket_requests.handover_resolved
		var pocket: int = int(picked[1])
		if pocket >= 0:
			var out: InventoryItem = Game.inventory.remove_from_slot(pocket, Game.inventory.slot_at(pocket).item.count)
			var find: ItemData = ItemCatalog.get_item(item_id)
			if find != null:
				Game.inventory.add(find, 1)
			if out != null:
				BuriedUse.bury(ctx, cell, out.item_id)
			return
	BuriedUse.bury(ctx, cell, item_id)
