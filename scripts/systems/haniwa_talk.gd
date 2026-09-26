class_name HaniwaTalk
extends RefCounted

## The gyroid outside each house plot (`ac_haniwa` / `ACTOR_PROP_HANIWA0`–`3`): what it says,
## how fast it dances and where it walks the player after "Save". Pure rules — the scene
## (`scenes/world/haniwa.gd`) only plays them. Wording stays in the imported ROM banks
## (`msg_*`); `owner_graph` stitches the ones this slice uses into one conversation.

## `aHNW_decide_msg_idx_dance`.
enum Msg { NO_OWNER, PROCEEDS, NORMAL, OTHER_OWNER, NEED_FRIEND }

## `aHNW_ACTION_*`. Everything from `CHECK_PROCEEDS` on is "in a conversation".
enum Action {
	WAIT,
	DANCE,
	CHECK_PROCEEDS,
	TALK_WITH_MASTER,
	TALK_WITH_MASTER2,
	TALK_END_WAIT,
	MENU_OPEN_WAIT,
	MENU_END_WAIT,
	TALK_WITH_GUEST,
	MENU_OPEN_WAIT_FOR_GUEST,
	MENU_END_WAIT_FOR_GUEST,
	ROOF_CHECK,
	SAVE_CHECK,
	SAVE_END_WAIT,
	PL_APPROACH_DOOR,
	DOOR_OPEN_WAIT,
	DOOR_OPEN_TIMER,
}

## `aHNW_set_talk_info_dance` msg_no table.
const MSG_NO_OWNER := 2356
const MSG_PROCEEDS := 2357
const MSG_NORMAL := 2341
const MSG_OTHER_OWNER := 2344
const MSG_NEED_FRIEND := 2350
## Owner menu lines reached from `MSG_NORMAL`'s choices.
const MSG_NEVER_MIND := 2342
const MSG_PROCESSED := 2343
const MSG_ENTER_HOUSE := 2349
const MSG_SAVE_CHECK := 2351
const MSG_SAVE_CANCEL := 2352
const MSG_OTHER_THINGS := 2353
const MSG_DOOR := 2354
const MSG_PROCESSED_AGAIN := 2355
## `aHNW_check_proceeds`: handed over (0x936) / pockets too full for the bags (0x937).
const MSG_PROCEEDS_TAKEN := 2358
const MSG_PROCEEDS_NO_ROOM := 2359
## Visitor side (`aHNW_talk_with_guest`): the owner's message, then Check items / Never mind.
const MSG_GUEST_MENU := 2345
const MSG_GUEST_BYE := 2346
const MSG_GUEST_THANKS := 2347
const MSG_GUEST_NOTHING := 2348
## `{choice:N}` ids (`select_data.bin`).
const CHOICE_SAVE := 94
const CHOICE_STORE := 20
const CHOICE_OTHER := 435
const CHOICE_NEVER_MIND := 21
const CHOICE_SAVE_YES := 195
const CHOICE_SAVE_NO := 61
const CHOICE_DOOR := 497
const CHOICE_MESSAGE := 601
const CHOICE_POST_PATTERN := 498
const CHOICE_REMOVE_PATTERN := 499
const CHOICE_CHECK_ITEMS := 22
## Every message the gyroid can say, merged into one conversation (`graph`).
const GRAPH_MSGS: Array[int] = [
	MSG_NORMAL, MSG_NEVER_MIND, MSG_PROCESSED, MSG_ENTER_HOUSE, MSG_SAVE_CHECK, MSG_SAVE_CANCEL,
	MSG_OTHER_THINGS, MSG_DOOR, MSG_PROCESSED_AGAIN, MSG_PROCEEDS, MSG_PROCEEDS_TAKEN,
	MSG_PROCEEDS_NO_ROOM, MSG_OTHER_OWNER, MSG_GUEST_MENU, MSG_GUEST_BYE, MSG_GUEST_THANKS,
	MSG_GUEST_NOTHING,
]
## Fired by the "That's right!" answer in `MSG_SAVE_CHECK` (`aHNW_save_check` CHOICE0).
const EVENT_SAVE := "haniwa_save"
## A choice that opens a submenu (`aHNW_menu_open_wait`): the talk ends, the menu runs, and
## the talk resumes at "Request processed." (`mMsg_ChangeMsgData(0x0927)`). `menu` is one of
## `MENU_*`.
const EVENT_MENU := "haniwa_menu"
const MENU_ENTRUST := "entrust"
const MENU_MESSAGE := "hboard"
const MENU_DOOR := "design"
const MENU_TAKE := "take"
## "Remove pattern" (`aHNW_roof_check` CHOICE1): `door_original = 0xFF`, SE 0x461.
const EVENT_DOOR_REMOVE := "haniwa_door_remove"
## Dialogue vars the graph branches on.
const VAR_START := "haniwa_start"
const VAR_HANDOVER := "haniwa_handover"
const VAR_HAS_ITEMS := "haniwa_has_items"
const START_MENU := "menu"
const START_PROCEEDS := "proceeds"
const START_RESUME := "resume"
const START_GUEST := "guest"
const START_GUEST_AFTER := "guest_after"

const DIALOGUE_ID := &"haniwa_owner"
## `m_npc.c` row for `ACTOR_PROP_HANIWA*`: name string 0x213, `mPr_SEX_OTHER`, voice 2.
const SPEAKER_NAME := "Gyroid"
const SOUND_SPEC := 2

## `aHNW_wait` / `aHNW_dance`: start dancing inside 80 GX, stop past 90 GX.
const DANCE_NEAR_GX := 80.0
const DANCE_FAR_GX := 90.0
## `actor->talk_distance`.
const TALK_DISTANCE_GX := 43.0
## `aHNW_search_player` / `aHNW_search_front`: `chase_angle(..., 0x0600)`, frame-scaled.
const TURN_STEP := 0x0600
## `aHNW_search_front` target_angle, per house plot (west plots look east of south).
const FRONT_ANGLE: Array[int] = [8000, -8000, 8000, -8000]
## `aHNW_common_process`: frame speed chases up by 0.05, down by 0.015 per frame.
const SPEED_UP := 0.05
const SPEED_DOWN := 0.015
## `hnw_move` is keyframes 1 → 9 on repeat.
const MOVE_FIRST_FRAME := 1.0
const MOVE_LAST_FRAME := 9.0

## `aHNW_pl_approach_door`: `goal_pos[house][stage]` as GX offsets from the gyroid (unit
## centre of FG ut (3,5) / (12,5) / (3,12) / (12,12)). Stage 0 steps round the gyroid, stage 1
## stops at the door. `chk_posX` flips to stage 1 once the player crosses 35 GX to the
## house side of the gyroid.
const DOOR_GOALS_GX: Array = [
	[Vector2(38.0, 40.0), Vector2(50.0, -26.0)],
	[Vector2(-38.0, 40.0), Vector2(-51.0, -26.0)],
	[Vector2(38.0, 40.0), Vector2(50.0, -25.0)],
	[Vector2(-38.0, 40.0), Vector2(-51.0, -25.0)],
]
const DOOR_STAGE_X_GX: Array[float] = [35.0, -35.0, 35.0, -35.0]
## `mPlib_request_main_demo_walk_type1(..., 3.0f, ...)` — demo walk speed and arrive radius.
const DOOR_WALK_SPEED_GX := 3.0
const DOOR_ARRIVE_GX := 3.0
## Give up and open the door anyway after 160 frames.
const DOOR_WALK_FRAMES := 160


## `aHNW_decide_msg_idx_dance`. `owner_is_player`: this plot's house is the player's.
static func decide_msg(
	has_owner: bool,
	owner_is_player: bool,
	has_saved: bool,
	first_job_active: bool,
	friend_count: int,
	proceeds: int
) -> Msg:
	if not has_owner:
		return Msg.NO_OWNER
	if not owner_is_player:
		return Msg.OTHER_OWNER
	if not has_saved and first_job_active and friend_count == 0:
		return Msg.NEED_FRIEND
	if proceeds != 0:
		return Msg.PROCEEDS
	return Msg.NORMAL


static func msg_no(msg: Msg) -> int:
	match msg:
		Msg.NO_OWNER:
			return MSG_NO_OWNER
		Msg.PROCEEDS:
			return MSG_PROCEEDS
		Msg.OTHER_OWNER:
			return MSG_OTHER_OWNER
		Msg.NEED_FRIEND:
			return MSG_NEED_FRIEND
	return MSG_NORMAL


## `aHNW_setupAction`'s target frame speed. `current` is the speed before the change: an
## ownerless gyroid that has already stopped stays stopped.
static func anim_speed(action: Action, has_owner: bool, owner_is_player: bool, current: float) -> float:
	if action >= Action.CHECK_PROCEEDS:
		return 0.3
	if not has_owner:
		return 0.075 if current != 0.0 else current
	if not owner_is_player:
		return 0.1
	if action == Action.WAIT or action == Action.DOOR_OPEN_TIMER:
		return 0.3
	return 0.45


## `aHNW_setupAction` / `aHNW_common_process`: an ownerless gyroid outside a conversation
## plays its clip out once and freezes (`cKF_FRAMECONTROL_STOP`).
static func stops_at_end(action: Action, has_owner: bool, speed: float) -> bool:
	return not has_owner and action < Action.CHECK_PROCEEDS and speed <= 0.1


## `chase_f` towards the target frame speed (faster up than down), `ticks` 60 Hz frames.
static func chase_speed(current: float, target: float, ticks: float = 1.0) -> float:
	var step: float = SPEED_UP if target > current else SPEED_DOWN
	return move_toward(current, target, step * ticks)


## Yaw the gyroid turns to this frame: the player when owned or talking, else its plot's
## front angle. Radians, Godot = AC convention (0 faces +Z).
static func look_yaw(house_idx: int, has_owner: bool, action: Action, player_yaw: float) -> float:
	if has_owner or action >= Action.CHECK_PROCEEDS:
		return player_yaw
	return MLib.s16_to_rad(FRONT_ANGLE[clampi(house_idx, 0, 3)])


## `chase_angle(rot, target, 0x0600)`: scaled by the 30 Hz game frame (`game_GameFrame_2F`),
## so it turns `TURN_STEP` × 30 per second whatever the tick rate.
static func chase_yaw(current: float, target: float, delta: float) -> float:
	var step: float = MLib.s16_to_rad(TURN_STEP) * DecompTime.FRAME_HZ * delta
	var diff: float = wrapf(target - current, -PI, PI)
	if absf(diff) <= step:
		return target
	return current + step * signf(diff)


## `aHNW_pl_approach_door` stage for a player `offset_gx` from the gyroid (x only matters).
static func door_stage(house_idx: int, offset_gx: Vector2) -> int:
	var i: int = clampi(house_idx, 0, 3)
	var chk: float = DOOR_STAGE_X_GX[i]
	return 1 if (chk - offset_gx.x) * signf(chk) <= 0.0 else 0


static func door_goal_gx(house_idx: int, stage: int) -> Vector2:
	var row: Array = DOOR_GOALS_GX[clampi(house_idx, 0, 3)]
	return row[clampi(stage, 0, 1)]


## Every gyroid message (`GRAPH_MSGS`) merged into one conversation, node ids
## `m<msg>_<node>`, entered through a `start` branch on `VAR_START`. Choices that open a submenu
## end the talk with `EVENT_MENU`; the host runs the menu and replays from `START_RESUME`.
## Null when the ROM banks are not converted.
static func graph() -> DialogueData:
	var nodes: Dictionary = {}
	for msg: int in GRAPH_MSGS:
		var data: DialogueData = DialogueCatalog.conversation(StringName("msg_%d" % msg))
		if data == null:
			return null
		data.ensure_loaded()
		for key: Variant in data.nodes:
			var rec: Dictionary = (data.nodes[key] as Dictionary).duplicate(true)
			if rec.has("next"):
				rec["next"] = _node_ref(msg, str(rec["next"]))
			if rec.has("options"):
				rec["options"] = _options(msg, rec["options"])
			nodes[_node_id(msg, str(key))] = rec
	## `aHNW_check_proceeds` picks the follow-up once the income line has shown.
	var income_end: String = _last_node(nodes, MSG_PROCEEDS)
	if income_end != "":
		(nodes[income_end] as Dictionary)["next"] = "proceeds_branch"
	nodes["proceeds_branch"] = _branch(VAR_HANDOVER, {"yes": _node_id(MSG_PROCEEDS_TAKEN, "p0")},
		_node_id(MSG_PROCEEDS_NO_ROOM, "p0"))
	## `aHNW_talk_with_guest` CHOICE0: nothing held → 0x92C, else the take menu.
	nodes["guest_check"] = _branch(VAR_HAS_ITEMS, {"yes": "guest_take"}, _node_id(MSG_GUEST_NOTHING, "p0"))
	nodes["guest_take"] = {"type": "event", "events": [{"op": EVENT_MENU, "menu": MENU_TAKE}]}
	nodes["start"] = _branch(VAR_START, {
		START_PROCEEDS: _node_id(MSG_PROCEEDS, "p0"),
		START_RESUME: _node_id(MSG_PROCESSED, "p0"),
		START_GUEST: _node_id(MSG_OTHER_OWNER, "p0"),
		START_GUEST_AFTER: _node_id(MSG_GUEST_THANKS, "p0"),
	}, _node_id(MSG_NORMAL, "p0"))
	return DialogueData.from_dict({"id": String(DIALOGUE_ID), "start": "start", "nodes": nodes})


static func _branch(var_name: String, arms: Dictionary, fallback: String) -> Dictionary:
	var when: Array = []
	for value: String in arms:
		when.append({"if": {"var_eq": {"name": var_name, "value": value}}, "goto": arms[value]})
	when.append({"goto": fallback})
	return {"type": "branch", "when": when}


## The node of message `msg` with no `next` (its last line / event).
static func _last_node(nodes: Dictionary, msg: int) -> String:
	var prefix: String = "m%d_" % msg
	for key: String in nodes:
		if key.begins_with(prefix) and not (nodes[key] as Dictionary).has("next") \
				and not (nodes[key] as Dictionary).has("options"):
			return key
	return ""


## Choice wiring: submenu choices end the talk with `EVENT_MENU`; the rest keep the ROM's
## `goto`, except where the actor supplies the follow-up itself.
static func _options(msg: int, raw: Variant) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for entry: Variant in raw as Array:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var opt: Dictionary = (entry as Dictionary).duplicate(true)
		var choice: int = _choice_id(str(opt.get("text", "")))
		opt["goto"] = _node_ref(msg, str(opt.get("goto", "")))
		match choice:
			CHOICE_STORE:
				opt["events"] = [{"op": EVENT_MENU, "menu": MENU_ENTRUST}]
				opt["goto"] = ""
			CHOICE_MESSAGE:
				opt["events"] = [{"op": EVENT_MENU, "menu": MENU_MESSAGE}]
				opt["goto"] = ""
			CHOICE_POST_PATTERN:
				opt["events"] = [{"op": EVENT_MENU, "menu": MENU_DOOR}]
				opt["goto"] = ""
			CHOICE_REMOVE_PATTERN:
				opt["events"] = [{"op": EVENT_DOOR_REMOVE}]
			CHOICE_SAVE_YES:
				if msg == MSG_SAVE_CHECK:
					opt["events"] = [{"op": EVENT_SAVE}]
			CHOICE_CHECK_ITEMS:
				opt["goto"] = "guest_check"
			CHOICE_NEVER_MIND:
				if msg == MSG_GUEST_MENU:
					opt["goto"] = _node_id(MSG_GUEST_BYE, "p0")
		if choice >= 0:
			opt["text"] = DialogueCatalog.choice_label(choice)
		out.append(opt)
	return out


## `{choice:N}` → N, or −1.
static func _choice_id(text: String) -> int:
	if not text.begins_with("{choice:") or not text.ends_with("}"):
		return -1
	return text.substr(8, text.length() - 9).to_int()


## A `next` / `goto` inside message `msg`: another message's start, a node of the same
## message, or "" (end).
static func _node_ref(msg: int, ref: String) -> String:
	if ref == "":
		return ""
	if ref.begins_with("msg_"):
		return _node_id(ref.substr(4).to_int(), "p0")
	return _node_id(msg, ref)


static func _node_id(msg: int, key: String) -> String:
	return "m%d_%s" % [msg, key]
