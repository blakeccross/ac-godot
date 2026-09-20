class_name FurnitureGrip
extends RefCounted

## Player ↔ furniture handling in the player's own house (`ac_my_room` contact code:
## `aMR_ManageMoveBottun`, `aMR_MngPush/PullDirectTimer`, `aMR_PlacePush/Pull/KurukuruFurniture`).
##
## Press A against a piece and the player grips it. While A stays down the stick moves it:
## away from it pulls, into it pushes, sideways turns it. Letting go of A inside 14 ticks is a
## tap — the ordinary "use" verb (open a drawer, toggle, …). B, from a few units back, picks a
## piece up. Everything here is pure grid logic on an `IndoorSession`; the player script feeds
## it input at 60 Hz and plays the animations the returned events name.

enum Phase { IDLE, GRIPPED, BUSY }
enum ContactSide { FRONT, BACK, LEFT, RIGHT }

const TICK_HZ := 60.0
## `switch_timer < 14`: a shorter A press is a tap.
const TAP_TICKS := 14
## `push_timer > 16` / `pull_timer > 16`.
const MOVE_TICKS := 16
## `move_pR >= 0.8` and the axis component above 0.8.
const STICK_FULL := 0.8
## `aMR_CheckControllerNeutral`.
const STICK_NEUTRAL := 0.086
## How near the player must be to the face of a piece to grip it (metres).
const CONTACT_DIST := 1.6
## `aMR_SearchPickupFurniture`: units in front within 56 GX.
const PICKUP_REACH := 56.0 * FieldCatalog.GX_TO_METERS

var phase: Phase = Phase.IDLE
var placement_id: StringName = &""
## Direction the player faces (toward the piece).
var facing: WorldGrid.Facing = WorldGrid.Facing.NORTH
var pivot: Vector2i = Vector2i.ZERO
var side: ContactSide = ContactSide.FRONT
var press_ticks: int = 0
var push_ticks: int = 0
var pull_ticks: int = 0
var allow_rotation: bool = true
## After a blocked attempt the stick has to come back before the next one (`push_bubu`).
var need_neutral: bool = false

var _accum: float = 0.0


func is_active() -> bool:
	return phase != Phase.IDLE


func reset() -> void:
	phase = Phase.IDLE
	placement_id = &""
	press_ticks = 0
	push_ticks = 0
	pull_ticks = 0
	allow_rotation = true
	need_neutral = false
	_accum = 0.0


## The floor piece the player is up against, or `{}`. `{ placement, data, pivot, side, nice_pos }`.
static func find_contact(session: IndoorSession, player_pos: Vector3, face: WorldGrid.Facing) -> Dictionary:
	if session == null or session.room == null:
		return {}
	var grid: WorldGrid = session.grid
	var player_cell: Vector2i = grid.world_to_cell(player_pos)
	var target: Vector2i = grid.step(player_cell, face)
	var who: StringName = grid.occupant_at(target)
	if who == &"":
		return {}
	var entry: FurniturePlacement = session.room.placement_by_id(who)
	var data: FurnitureData = session.furniture_of(entry.furniture_id) if entry != null else null
	if data == null or not data.blocks_walk or data.placement == FurnitureData.Placement.WALL:
		return {}
	var corner: Vector3 = grid.cell_corner(target)
	var size: float = grid.cell_size
	var gap: float = 0.0
	match face:
		WorldGrid.Facing.NORTH:
			gap = player_pos.z - (corner.z + size)
		WorldGrid.Facing.SOUTH:
			gap = corner.z - player_pos.z
		WorldGrid.Facing.EAST:
			gap = corner.x - player_pos.x
		_:
			gap = player_pos.x - (corner.x + size)
	if gap > CONTACT_DIST:
		return {}
	var nice: Vector3 = grid.cell_to_world(player_cell)
	nice.y = player_pos.y
	## Line up with the contacted unit: keep the lateral offset, clamped inside it.
	if face == WorldGrid.Facing.NORTH or face == WorldGrid.Facing.SOUTH:
		nice.x = clampf(player_pos.x, corner.x + 0.2, corner.x + size - 0.2)
	else:
		nice.z = clampf(player_pos.z, corner.z + 0.2, corner.z + size - 0.2)
	return {
		"placement": entry,
		"data": data,
		"pivot": target,
		"side": side_of(entry, face),
		"nice_pos": nice,
	}


## Which face of the piece the player is on, relative to the way the piece faces
## (`aMR_CONTACT_DIR_*`). Drawers, wardrobes and music players only answer from the front.
static func side_of(entry: FurniturePlacement, player_facing: WorldGrid.Facing) -> ContactSide:
	var toward_player: int = (int(player_facing) + 2) % WorldGrid.FACING_COUNT
	var rel: int = (toward_player - int(entry.facing) + WorldGrid.FACING_COUNT) % WorldGrid.FACING_COUNT
	match rel:
		0:
			return ContactSide.FRONT
		2:
			return ContactSide.BACK
		1:
			return ContactSide.LEFT
		_:
			return ContactSide.RIGHT


## What B would pick up: the small piece on the unit in front first, else the floor piece
## (`aMR_SearchPickupFurniture` searches the layer above before the one below), and only
## within 56 GX of that unit's centre.
static func find_pickup(session: IndoorSession, player_pos: Vector3, face: WorldGrid.Facing) -> StringName:
	if session == null or session.room == null:
		return &""
	var grid: WorldGrid = session.grid
	var target: Vector2i = grid.step(grid.world_to_cell(player_pos), face)
	var center: Vector3 = grid.cell_to_world(target)
	if Vector2(player_pos.x - center.x, player_pos.z - center.z).length() > PICKUP_REACH:
		return &""
	var rider: FurniturePlacement = session.surface_item_at(target)
	if rider != null:
		return rider.id
	return grid.occupant_at(target)


## A pressed against `contact`. Returns false when there is nothing to grip.
func press(session: IndoorSession, player_pos: Vector3, face: WorldGrid.Facing) -> Dictionary:
	if phase != Phase.IDLE:
		return {}
	var contact: Dictionary = find_contact(session, player_pos, face)
	if contact.is_empty():
		return {}
	var entry: FurniturePlacement = contact["placement"] as FurniturePlacement
	phase = Phase.GRIPPED
	placement_id = entry.id
	facing = face
	pivot = contact["pivot"] as Vector2i
	side = contact["side"] as ContactSide
	press_ticks = 0
	push_ticks = 0
	pull_ticks = 0
	allow_rotation = true
	need_neutral = false
	_accum = 0.0
	return contact


## Player finished the push / pull / turn animation.
func finish_busy() -> void:
	if phase == Phase.BUSY:
		phase = Phase.GRIPPED
		push_ticks = 0
		pull_ticks = 0


## Advance by `delta` seconds. Returns events in order: `tap`, `release`, `move`, `rotate`, `bubu`.
func advance(
	delta: float,
	session: IndoorSession,
	a_held: bool,
	stick: Vector2,
	player_pos: Vector3
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if phase == Phase.IDLE:
		return out
	_accum += delta * TICK_HZ
	while _accum >= 1.0 and phase != Phase.IDLE:
		_accum -= 1.0
		out.append_array(_tick(session, a_held, stick, player_pos))
	return out


func _tick(session: IndoorSession, a_held: bool, stick: Vector2, player_pos: Vector3) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not a_held:
		if press_ticks < TAP_TICKS and phase == Phase.GRIPPED:
			out.append({"op": "tap", "id": placement_id, "side": side})
		else:
			out.append({"op": "release", "id": placement_id})
		reset()
		return out
	if press_ticks < TAP_TICKS:
		press_ticks += 1
	if phase == Phase.BUSY:
		return out
	var entry: FurniturePlacement = session.room.placement_by_id(placement_id) if session.room != null else null
	if entry == null:
		reset()
		return out
	var toward: Vector2i = session.grid.step(Vector2i.ZERO, facing)
	var toward_v := Vector2(float(toward.x), float(toward.y))
	var along: float = stick.dot(toward_v)
	var across: float = stick.dot(Vector2(-toward_v.y, toward_v.x))
	var full: bool = stick.length() >= STICK_FULL
	if stick.x <= STICK_NEUTRAL and stick.x >= -STICK_NEUTRAL and stick.y <= STICK_NEUTRAL and stick.y >= -STICK_NEUTRAL:
		allow_rotation = true
		need_neutral = false
	var pushing: bool = full and along > STICK_FULL
	var pulling: bool = full and along < -STICK_FULL
	var turning: bool = full and absf(across) > STICK_FULL
	if need_neutral and (pushing or pulling):
		push_ticks = 0
		pull_ticks = 0
		return out
	push_ticks = push_ticks + 1 if pushing else 0
	pull_ticks = pull_ticks + 1 if pulling else 0
	if push_ticks > MOVE_TICKS:
		push_ticks = 0
		out.append(_try_push(session, entry, toward, player_pos))
	elif pull_ticks > MOVE_TICKS:
		pull_ticks = 0
		out.append(_try_pull(session, entry, toward, player_pos))
	elif turning and allow_rotation:
		allow_rotation = false
		out.append(_try_rotate(session, entry, toward_v, stick, player_pos))
	return out


func _try_push(session: IndoorSession, entry: FurniturePlacement, toward: Vector2i, player_pos: Vector3) -> Dictionary:
	var from_cell: Vector2i = entry.cell
	var before: Array[Vector2i] = session.grid.cells_of(entry.id)
	if not session.move_placement(entry.id, toward):
		need_neutral = true
		return {"op": "bubu", "id": entry.id}
	phase = Phase.BUSY
	pivot += toward
	var step_m: Vector3 = Vector3(float(toward.x), 0.0, float(toward.y)) * session.grid.cell_size
	return {
		"op": "move",
		"kind": &"push",
		"id": entry.id,
		"vacated": _vacated(session, entry.id, before),
		"from_cell": from_cell,
		"to_cell": entry.cell,
		"player_from": player_pos,
		"player_to": player_pos + step_m,
	}


func _try_pull(session: IndoorSession, entry: FurniturePlacement, toward: Vector2i, player_pos: Vector3) -> Dictionary:
	var away: Vector2i = -toward
	var grid: WorldGrid = session.grid
	## The player backs up one unit with it (`aMR_CheckPullPlayerObstacle`).
	var behind: Vector2i = grid.world_to_cell(player_pos) + away
	var blocked: bool = (
		not session.room.is_inner(behind)
		or session.room.is_exit_cell(behind)
		or (grid.occupant_at(behind) != &"" and grid.occupant_at(behind) != entry.id)
	)
	var from_cell: Vector2i = entry.cell
	var before: Array[Vector2i] = grid.cells_of(entry.id)
	if blocked or not session.move_placement(entry.id, away):
		need_neutral = true
		return {"op": "bubu", "id": entry.id}
	phase = Phase.BUSY
	pivot += away
	var step_m: Vector3 = Vector3(float(away.x), 0.0, float(away.y)) * grid.cell_size
	return {
		"op": "move",
		"kind": &"pull",
		"id": entry.id,
		"vacated": _vacated(session, entry.id, before),
		"from_cell": from_cell,
		"to_cell": entry.cell,
		"player_from": player_pos,
		"player_to": player_pos + step_m,
	}


func _try_rotate(
	session: IndoorSession,
	entry: FurniturePlacement,
	toward_v: Vector2,
	stick: Vector2,
	player_pos: Vector3
) -> Dictionary:
	## Stick to the player's left drags the near edge left: a counter-clockwise turn.
	var away_v: Vector2 = -toward_v
	var cross: float = away_v.x * stick.y - away_v.y * stick.x
	var ccw: bool = cross < 0.0
	var steps: int = 1 if ccw else -1
	var player_cell: Vector2i = session.grid.world_to_cell(player_pos)
	var before: Array[Vector2i] = session.grid.cells_of(entry.id)
	if not session.rotate_about(entry.id, steps, pivot, player_cell):
		return {"op": "bubu", "id": entry.id}
	phase = Phase.BUSY
	return {"op": "rotate", "id": entry.id, "vacated": _vacated(session, entry.id, before), "ccw": ccw, "pivot": pivot, "cell": entry.cell, "facing": entry.facing}


## Cells a piece no longer covers after a move — where a cockroach may have been hiding
## (`aMR_GokiburiPos_*`).
func _vacated(session: IndoorSession, id: StringName, before: Array[Vector2i]) -> Array[Vector2i]:
	var now: Array[Vector2i] = session.grid.cells_of(id)
	var out: Array[Vector2i] = []
	for cell: Vector2i in before:
		if not now.has(cell):
			out.append(cell)
	return out
