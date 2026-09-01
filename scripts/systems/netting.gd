class_name Netting
extends RefCounted

## Net swing session. Behavioral analog of `SWING_NET` → `PULL_NET` → `NOTICE_NET`
## in `m_player.h`. Not an autoload: `ToolUse` resolves the catch on the swing
## frame, then the player plays pull/notice beats.

## `Player_actor_Item_CheckLocalCapture_forNet`: net column length 50 GX (60 gold).
const SWING_LENGTH := 50.0 * FieldCatalog.GX_TO_METERS
const SWING_RADIUS := 15.0 * FieldCatalog.GX_TO_METERS
## Catch resolves after animation frame 6 (`Player_actor_CatchSomethingCheck_Swing_net`).
const SWING_CATCH_FRAME := 6.0

const PULL := &"ply_1_get_m1"
const SHOW := &"ply_1_yatta2"
const PUTAWAY := &"ply_1_get_putaway1"
const NET_PULL := &"net_swing1"
const NET_SHOW := &"kamae_main_m1"

const SHOW_YAW := 0.0
const SHOW_TURN_HZ := 60.0
const SHOW_TURN_FRACTION := 0.292893
const SHOW_TURN_MAX_STEP := TAU * 2500.0 / 65536.0
const SHOW_TURN_MIN_STEP := TAU * 50.0 / 65536.0
const SHOW_HOLD_SECONDS := 42.0 / 60.0


class Outcome:
	var missed: bool = false
	var pockets_full: bool = false
	var bug: BugData = null
	var catch_msg: int = 0

	func caught() -> bool:
		return bug != null and not pockets_full


class CatchBeat:
	var player_anim: StringName = &""
	var tool_anim: StringName = &""
	var face_camera: bool = false
	var hold: float = 0.0
	var catch_msg: int = 0
	var bug: BugData = null
	var pockets_full: bool = false

	func _init(
		p_player: StringName = &"",
		p_tool: StringName = &"",
		p_face_camera: bool = false,
		p_hold: float = 0.0,
		p_catch_msg: int = 0,
		p_bug: BugData = null,
		p_pockets_full: bool = false
	) -> void:
		player_anim = p_player
		tool_anim = p_tool
		face_camera = p_face_camera
		hold = p_hold
		catch_msg = p_catch_msg
		bug = p_bug
		pockets_full = p_pockets_full


static var _reel: Array[CatchBeat] = []


static func field_of(ctx: InteractionContext) -> BugField:
	if ctx == null or ctx.world == null:
		return null
	return ctx.world.get("bugs") as BugField


static func swing(ctx: InteractionContext, origin: Vector3, direction: Vector3) -> Outcome:
	var out := Outcome.new()
	var field: BugField = field_of(ctx)
	if field != null:
		field.notify_net_swing(origin, direction)
		var actor: BugActor = field.find_in_net(origin, direction)
		if actor != null and actor.bug != null:
			var inventory: Inventory = ctx.inventory if ctx != null else null
			if inventory == null or not inventory.has_space_for(actor.bug, 1):
				out.pockets_full = true
				out.bug = actor.bug
				out.catch_msg = actor.bug.catch_msg
				actor.release()
			else:
				inventory.add(actor.bug, 1)
				actor.catch()
				out.bug = actor.bug
				out.catch_msg = actor.bug.catch_msg
		else:
			out.missed = true
	else:
		out.missed = true
	_reel = catch_beats(out)
	return out


static func catch_beats(out: Outcome) -> Array[CatchBeat]:
	if out != null and out.bug != null:
		return [
			CatchBeat.new(PULL, NET_PULL),
			CatchBeat.new(
				SHOW, NET_SHOW, true, SHOW_HOLD_SECONDS, out.catch_msg, out.bug, out.pockets_full
			),
		]
	return []


static func take_catch_beats() -> Array[CatchBeat]:
	var beats: Array[CatchBeat] = _reel
	_reel = []
	return beats


static func reset() -> void:
	_reel = []
