class_name FurnitureSeat
extends RefCounted

## Sitting and lying down (`aMR_SitDownFurniture`, `aMR_JudgeGoToBed`). No button: walk into
## a chair from a side it accepts, or into the long side of a bed, holding the stick straight at
## it for more than 14 ticks. Works in every room, not just the player's own.

enum Rest { NONE, SIT, LIE }

const TICK_HZ := 60.0
## `sit_timer > 14` / `bed_timer > 14`.
const HOLD_TICKS := 14
## `aMR_3DStickNuetral` + `move_pR > 0.6`.
const STICK_MIN := 0.6
## Straight-on tolerance: 15° to sit, 35° to lie down.
const SIT_COS := 0.9659
const BED_COS := 0.8192
## `Player_actor_request_main_standup`: the player steps 35 GX out of the seat.
const STAND_STEP := 35.0 * FieldCatalog.GX_TO_METERS

var sit_ticks: int = 0
var bed_ticks: int = 0
var _accum: float = 0.0


func reset() -> void:
	sit_ticks = 0
	bed_ticks = 0
	_accum = 0.0


## Advance `delta` seconds of held stick. Returns `{}` until a rest starts, then
## `{ kind, id, pos, yaw_facing, head, approach }`.
func poll(
	delta: float,
	session: IndoorSession,
	player_pos: Vector3,
	face: WorldGrid.Facing,
	stick: Vector2
) -> Dictionary:
	_accum += delta * TICK_HZ
	var result: Dictionary = {}
	while _accum >= 1.0:
		_accum -= 1.0
		result = _tick(session, player_pos, face, stick)
		if not result.is_empty():
			reset()
			return result
	return result


func _tick(session: IndoorSession, player_pos: Vector3, face: WorldGrid.Facing, stick: Vector2) -> Dictionary:
	var contact: Dictionary = FurnitureGrip.find_contact(session, player_pos, face)
	if contact.is_empty() or stick.length() < STICK_MIN:
		sit_ticks = 0
		bed_ticks = 0
		return {}
	var toward: Vector2i = session.grid.step(Vector2i.ZERO, face)
	var aim: float = stick.normalized().dot(Vector2(float(toward.x), float(toward.y)))
	var entry: FurniturePlacement = contact["placement"] as FurniturePlacement
	var data: FurnitureData = contact["data"] as FurnitureData
	var side: int = contact["side"] as int
	var pivot: Vector2i = contact["pivot"] as Vector2i
	sit_ticks = sit_ticks + 1 if (aim >= SIT_COS and can_sit_from(data, side)) else 0
	bed_ticks = bed_ticks + 1 if (aim >= BED_COS and can_lie_from(session, entry, data, face)) else 0
	if sit_ticks > HOLD_TICKS:
		var seat: Vector3 = session.grid.cell_to_world(pivot)
		seat.y = player_pos.y
		return {
			"kind": Rest.SIT,
			"id": entry.id,
			"pos": seat,
			## Back into the seat: face the way the piece opens.
			"yaw_facing": ((int(face) + 2) % WorldGrid.FACING_COUNT) as WorldGrid.Facing,
			"approach": player_pos,
		}
	if bed_ticks > HOLD_TICKS:
		var bed: Vector3 = session.grid.cell_to_world(pivot)
		bed.y = player_pos.y
		var head: WorldGrid.Facing = head_direction(entry.facing, session.grid)
		return {
			"kind": Rest.LIE,
			"id": entry.id,
			"pos": bed,
			"yaw_facing": head,
			"head": head,
			"approach": player_pos,
			"from_left": session.grid.rotate_facing(head, 1) == face,
		}
	return {}


## `aME_sit_data`: which face of the piece takes a seat (`contact_action` bits).
static func can_sit_from(data: FurnitureData, side: int) -> bool:
	if data == null:
		return false
	match data.contact:
		FurnitureData.Contact.CHAIR_ANY:
			return true
		FurnitureData.Contact.CHAIR_FRONT, FurnitureData.Contact.SOFA:
			return side == FurnitureGrip.ContactSide.FRONT
	return false


## Beds are entered across the long side; a double bed from any side.
static func can_lie_from(session: IndoorSession, entry: FurniturePlacement, data: FurnitureData, face: WorldGrid.Facing) -> bool:
	if data == null or not data.is_bed():
		return false
	var cells: Array[Vector2i] = session.grid.cells_of(entry.id)
	if cells.size() < 2:
		return true
	var xs: Dictionary = {}
	var zs: Dictionary = {}
	for cell: Vector2i in cells:
		xs[cell.x] = true
		zs[cell.y] = true
	if xs.size() > 1 and zs.size() > 1:
		return true
	## Long axis east–west → walk in from north or south, and the other way round.
	var along_x: bool = xs.size() > 1
	var across: bool = face == WorldGrid.Facing.NORTH or face == WorldGrid.Facing.SOUTH
	return across if along_x else not across


## `aMR_GetBedHeadDirect`: the way the pillow end points, from the way the bed faces.
static func head_direction(bed_facing: WorldGrid.Facing, grid: WorldGrid) -> WorldGrid.Facing:
	return grid.rotate_facing(bed_facing, -1)


## Where the player ends up after getting out of a chair: `STAND_STEP` ahead of the seat
## (`Player_actor_request_main_standup`). `{}` when that spot is not clear.
static func stand_spot(session: IndoorSession, seat_pos: Vector3, seat_facing: WorldGrid.Facing) -> Dictionary:
	var grid: WorldGrid = session.grid
	var dir: Vector2i = grid.step(Vector2i.ZERO, seat_facing)
	var spot: Vector3 = seat_pos + Vector3(float(dir.x), 0.0, float(dir.y)) * STAND_STEP
	if not _clear(session, spot):
		spot = seat_pos + Vector3(float(dir.x), 0.0, float(dir.y)) * grid.cell_size
		if not _clear(session, spot):
			return {}
	return {"pos": spot}


## Getting out of a bed puts the player back on the side they came in from.
static func bed_exit_spot(session: IndoorSession, approach: Vector3) -> Dictionary:
	var grid: WorldGrid = session.grid
	var spot: Vector3 = grid.cell_to_world(grid.world_to_cell(approach))
	spot.y = approach.y
	if not _clear(session, spot):
		return {}
	return {"pos": spot}


static func _clear(session: IndoorSession, spot: Vector3) -> bool:
	var cell: Vector2i = session.grid.world_to_cell(spot)
	return session.room.is_inner(cell) and session.grid.occupant_at(cell) == &""
