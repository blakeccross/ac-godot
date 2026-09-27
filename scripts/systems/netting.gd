class_name Netting
extends RefCounted

## What happens around a net swing: building each tick's `NetSwing.Probe`, and the catch
## sequence once the net comes back with something in it. Behavioral port of
## `m_player_main_pull_net` → `notice_net` → `putaway_net`. Not an autoload; the player
## drives the timing and asks this for the numbers and the side effects.
##
## - **Pull** (`GET_M1`, 52 keyframes): the insect rides hidden in the net until keyframe 15,
##   then sits in the left hand. Past keyframe 17 the player turns to face the camera
##   (yaw 0). A report timer counts ticks from the start and opens the catch message at 50,
##   whether or not the clip is done.
## - **Notice**: on entry the insect goes into the pockets (`Player_actor_putin_item`) and
##   onto the catch record (`mSM_COLLECT_INSECT_SET`), and the player snaps to yaw 0. If this
##   species was the last one missing from the record, the report is 0xA4E and continues into
##   0xA4F with `YATTA2` and fanfare 0x4B. With full pockets it continues into 0xA4D, a
##   yes / no on swapping something out; no lets the insect go.
## - **Put-away** (`PUTAWAY_M1`, 19 keyframes, `GASAGOSO`): the insect shrinks ×0.89125 a tick
##   until keyframe 17 and is gone from the hand there.

const ANIM_PULL := &"ply_1_get_m1"
const TOOL_PULL := &"get_m1"
const ANIM_YATTA := &"ply_1_yatta2"
const TOOL_YATTA := &"yatta_m1"
const ANIM_PUTAWAY := &"ply_1_putaway_m1"
const TOOL_PUTAWAY := &"kamae_main_m1"

## Keyframe counts (`cKF_ba_r_ply_1_get_m1`, `_yatta2`, `_putaway_m1`).
const PULL_FRAMES := 52.0
const YATTA_FRAMES := 53.0
const PUTAWAY_FRAMES := 19.0
const FRAME_SPEED := 0.5
## `Player_actor_CorrectSomething_Pull_net`: net → left hand after this keyframe.
const PULL_TO_HAND_FRAME := 15.0
## `Player_actor_Movement_Pull_net`: turn toward the camera after this keyframe.
const PULL_TURN_FRAME := 17.0
const SHOW_YAW := 0.0
## `Player_actor_MessageControl_Pull_net`: ticks until the report opens.
const PULL_REPORT_TICKS := 50.0
## `Player_actor_CorrectSomething_Putaway_net`.
const PUTAWAY_GONE_FRAME := 17.0
const PUTAWAY_SHRINK := 0.89125

## `Player_actor_Get_mushi_msg_num`.
const MUSHI_MSG_LOW := 0xA2C
const MUSHI_MSG_HIGH := 0x2FA1
const MUSHI_MSG_SPLIT := 0x20
## `main_pull->already_collected` (really `mSM_CHECK_LAST_INSECT_GET`) report and its
## continuation.
const LAST_GET_MSG := 0xA4E
const LAST_GET_CONTINUE_MSG := 0xA4F
## Pockets full: "swap something out?" with a yes / no.
const POCKETS_FULL_MSG := 0xA4D
## `mBGMPsComp_make_ps_fanfare`: the pull's jingle, and the collection-complete one.
const FANFARE_CATCH := 0x28
const FANFARE_COMPLETE := 0x4B
## `INSECT_ONLY_NUM`: insect types on the catch record (the five spirits are not).
const INSECT_RECORD_NUM := 40

## `aNPC_CoInfoData`: the villager collision pipe the net's triangle is tested against.
const NPC_PIPE_RADIUS_GX := 20.0
const NPC_PIPE_HEIGHT_GX := 30.0
## `Player_actor_SetPosition_OBJtoLine_forItem`: the triangle's third corner sits this far
## above the net's end.
const NET_TRI_RISE_GX := 10.0


## One catch, from the pull to the put-away.
class Catch:
	var bug: BugData = null
	var actor: BugActor = null
	## `mSM_CHECK_LAST_INSECT_GET` at the start of the pull.
	var completes_record: bool = false
	## `main_notice->not_full_pocket`.
	var banked: bool = false

	func report_msg() -> int:
		return LAST_GET_MSG if completes_record else Netting.mushi_msg(bug.type_index if bug != null else 0)


static func field_of(ctx: InteractionContext) -> BugField:
	if ctx == null or ctx.world == null:
		return null
	return ctx.world.get("bugs") as BugField


static func mushi_msg(type_index: int) -> int:
	if type_index < MUSHI_MSG_SPLIT:
		return MUSHI_MSG_LOW + type_index
	return MUSHI_MSG_HIGH + type_index


## `setup_main_Pull_net`: the caught insect leaves the field (it is drawn off the player
## from here on) and whether it is the last one the record is missing is fixed now.
static func begin_catch(caught: Object) -> Catch:
	var actor := caught as BugActor
	if actor == null or actor.bug == null:
		return null
	var out := Catch.new()
	out.actor = actor
	out.bug = actor.bug
	out.completes_record = completes_record(actor.bug.type_index)
	actor.catch()
	return out


## `mSM_CHECK_LAST_INSECT_GET`: every other insect is on the record and this one is not.
static func completes_record(type_index: int) -> bool:
	var book: CatalogBook = Game.catalog if Game != null else null
	if book == null or type_index < 0 or type_index >= INSECT_RECORD_NUM:
		return false
	if book.has_insect(type_index):
		return false
	return book.insect_count() == INSECT_RECORD_NUM - 1


## `setup_main_Notice_net`: pockets first, then the record, whether or not it fit.
static func bank(catch_: Catch, inventory: Inventory) -> bool:
	if catch_ == null or catch_.bug == null:
		return false
	catch_.banked = (
		inventory != null
		and inventory.has_space_for(catch_.bug, 1)
		and inventory.add(catch_.bug, 1) == 0
	)
	if Game != null and Game.catalog != null:
		Game.catalog.record_insect(catch_.bug.type_index)
	return catch_.banked


## `settle_main_Notice_net` / `release_creature`: a catch that did not go in the pockets is
## let go where the player is holding it, with `actor_specific = 1` (it flees).
static func release(catch_: Catch, field: BugField, at: Vector3) -> BugActor:
	if catch_ == null or catch_.bug == null or field == null:
		return null
	var habitat: BugData.Habitat = catch_.actor.habitat if catch_.actor != null else BugData.Habitat.FLYING
	return field.spawn(catch_.bug, habitat, at, true)


## Fills this tick's catch table and line result. `hand` is the right-hand joint's world
## transform (`right_hand_mtx`); `null_hand` draws the net off a fixed point ahead of the
## player instead (no skeleton loaded).
static func probe(
	ctx: InteractionContext, player_pos: Vector3, yaw: float, hand: Transform3D, has_hand: bool
) -> NetSwing.Probe:
	var out := NetSwing.Probe.new()
	var start: Vector3
	var end: Vector3
	if has_hand:
		out.net_pos = NetSwing.net_point(hand, NetSwing.NET_POS_GX)
		start = NetSwing.net_point(hand, NetSwing.NET_START_GX)
		end = NetSwing.net_point(hand, NetSwing.NET_END_GX)
	else:
		var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
		var at_hand: Vector3 = player_pos + Vector3(0.0, 20.0 * FieldCatalog.GX_TO_METERS, 0.0)
		out.net_pos = at_hand + fwd * (NetSwing.NET_POS_GX * FieldCatalog.GX_TO_METERS)
		start = at_hand + fwd * (NetSwing.NET_START_GX * FieldCatalog.GX_TO_METERS)
		end = at_hand + fwd * (NetSwing.NET_END_GX * FieldCatalog.GX_TO_METERS)
	var field: BugField = field_of(ctx)
	if field != null:
		out.candidates = field.net_candidates(player_pos)
	out.hit_actor = npc_on_line(ctx, start, end)
	out.line_bits = line_bits(ctx, start, end)
	return out


## `Player_actor_Check_OBJtoLine_forItem_net`: the net's triangle (start, end, end + 10 GX up)
## against the villagers' collision pipes.
static func npc_on_line(ctx: InteractionContext, start: Vector3, end: Vector3) -> Node3D:
	if ctx == null or ctx.actor == null or not ctx.actor.is_inside_tree():
		return null
	var radius: float = NPC_PIPE_RADIUS_GX * FieldCatalog.GX_TO_METERS
	var height: float = NPC_PIPE_HEIGHT_GX * FieldCatalog.GX_TO_METERS
	var rise: float = NET_TRI_RISE_GX * FieldCatalog.GX_TO_METERS
	for node: Node in ctx.actor.get_tree().get_nodes_in_group("villagers"):
		var villager := node as Node3D
		if villager == null or not villager.visible:
			continue
		var base: Vector3 = villager.global_position
		var t: float = _closest_t_xz(start, end, base)
		var p: Vector3 = start.lerp(end, t)
		if Vector2(p.x - base.x, p.z - base.z).length() > radius:
			continue
		if p.y + rise * t < base.y or p.y > base.y + height:
			continue
		return villager
	return null


## `mCoBG_LineCheck_RemoveFg(…, 7)`: wall, ground and water bits for the net's line.
static func line_bits(ctx: InteractionContext, start: Vector3, end: Vector3) -> int:
	var world: Object = ctx.world if ctx != null else null
	if world == null:
		return 0
	var layout := world.get("layout") as WorldData
	var grid := world.get("grid") as WorldGrid
	if layout == null or grid == null:
		return 0
	var bits: int = 0
	if FieldCollision.line_hits_wall(layout, grid, start, end):
		bits |= NetSwing.LINE_WALL
	## `mCoBG_LineGroundCheck`: any stretch of the line under the ground.
	for t: float in [0.25, 0.5, 0.75, 1.0]:
		var at: Vector3 = start.lerp(end, t)
		var y: float = FieldCollision.ground_y_at(layout, grid, at)
		if FieldCollision.has_floor(y) and at.y < y:
			bits |= NetSwing.LINE_GROUND
			break
	var ground: float = FieldCollision.ground_y_at(layout, grid, end)
	var cell: Vector2i = grid.world_to_cell(end)
	if grid.is_in_bounds(cell) and grid.terrain_at(cell) == WorldGrid.Terrain.WATER:
		if FieldCollision.has_floor(ground) and end.y <= ground + FieldCatalog.GX_TO_METERS:
			bits |= NetSwing.LINE_UNDERWATER
	return bits


static func _closest_t_xz(a: Vector3, b: Vector3, p: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var len2: float = ab.length_squared()
	if len2 <= 0.000001:
		return 0.0
	return clampf(Vector2(p.x - a.x, p.z - a.z).dot(ab) / len2, 0.0, 1.0)
