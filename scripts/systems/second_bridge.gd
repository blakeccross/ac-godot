class_name SecondBridge
extends RefCounted

## The second bridge (`Save_Get(bridge)`, `mEv_EVENT_SONCHO_BRIDGE_MAKE` / `_BRIDGE_MAKE`).
## Once all fifteen villagers live in town and there is no second bridge, Tortimer stands by
## the river Monday to Saturday when Gulliver isn't due (`init_weekly_event`). Each new day
## moves him one river acre upstream among those with a bridge spot (`RSV_BRIDGE0/1`,
## `bridge_man_start`), starting again at the mouth once he has been to the top. "Here is
## good!" orders the bridge in his acre for the next day (`aESC_talk_select`); from 6:00 that
## day it stands (`bridge_make_in`, `BRIDGE_A0/A1`). Not an autoload.
##
## `Game.bridge`: `{pending, exists, build, bx, bz, day, used, top, msg_no}` — `build` and
## `day` are `EventDates.ordinal`s, `used` / `top` are `bridge_flags`.

const SCENE := "res://scenes/world/second_bridge.tscn"
const GROUP := &"second_bridge"
const PERSIST := &"second_bridge"
## `aBridgeA_set_BgOffset` `rewrite_data`: attr, centre, nw, sw, se, ne, shape.
const REWRITE: Array = [
	[31, 4, 4, 4, 4, 4, 0],
	[27, 4, 0, 4, 4, 4, 1],
	[28, 4, 4, 0, 4, 4, 1],
	[29, 4, 4, 4, 0, 4, 1],
	[30, 4, 4, 4, 4, 0, 1],
	[31, 0, 0, 0, 0, 0, 0],
]
## `unit_offset_a0` / `_a1`: (dx, rewrite row, dz). Row 5 is an end: a full deck when it is
## level with the middle, else the bank as it is.
const UNITS_A0: Array[Vector3i] = [
	Vector3i(0, 0, 0), Vector3i(0, 1, -1), Vector3i(-1, 1, 0), Vector3i(1, 3, 0), Vector3i(0, 3, 1),
	Vector3i(1, 5, -1), Vector3i(-1, 5, 1),
]
const UNITS_A1: Array[Vector3i] = [
	Vector3i(0, 0, 0), Vector3i(0, 4, -1), Vector3i(1, 4, 0), Vector3i(-1, 2, 0), Vector3i(0, 2, 1),
	Vector3i(-1, 5, -1), Vector3i(1, 5, 1),
]
## `aBridgeA_actor_ct`: `world.position.y += 1.5`.
const LIFT_GX := 1.5
## `aESC_time_talk` / `aESC_owari_message` / pending lines.
const MSG_MORNING := 0x2F33
const MSG_DAY := 0x2F34
const MSG_EVENING := 0x2F35
const MSG_NIGHT := 0x2F36
const MSG_ASK := 0x2F37
const MSG_AGAIN := 0x2F3E
const MSG_STILL := 0x2F41
const MSG_ELSEWHERE := 0x2F39
const MSG_ELSEWHERE_TOP := 0x2F47
const MSG_PENDING := 0x2F44


static func new_state() -> Dictionary:
	return {"pending": false, "exists": false, "build": -1, "bx": -1, "bz": -1, "day": -1, "used": 0, "top": false, "msg_no": 0}


static func state() -> Dictionary:
	if Game.bridge.is_empty():
		Game.bridge = new_state()
	return Game.bridge


## The river acres with a bridge spot, from the source down (`river_stream` +
## `bridge_stand_river`). The port orders them north to south, west to east.
static func blocks(layout: WorldData) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if layout == null:
		return out
	for spot: Vector3i in layout.bridge_spots:
		var b: Vector2i = TownSpace.block_of_cell(Vector2i(spot.x, spot.y))
		if not out.has(b):
			out.append(b)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return out


## The spot in `block`: `RSV_BRIDGE0` first (`bridge_make_in`). (x, z, kind) or (-1, -1, -1).
static func spot_in(layout: WorldData, block: Vector2i) -> Vector3i:
	var best := Vector3i(-1, -1, -1)
	if layout == null:
		return best
	for spot: Vector3i in layout.bridge_spots:
		if TownSpace.block_of_cell(Vector2i(spot.x, spot.y)) != block:
			continue
		if best.z < 0 or spot.z < best.z:
			best = spot
	return best


## `init_weekly_event`: Saturdays, and Monday–Friday when Gulliver isn't due.
static func tortimer_due(weekday: int, gulliver_today: bool, residents_full: bool, foreigner: bool) -> bool:
	if not (weekday == 6 or (weekday != 0 and not gulliver_today)):
		return false
	return residents_full and not foreigner and not bool(state().get("exists", false))


## `bridge_day` / `bridge_flags.raw++` once per day he comes.
static func note_day(today: int) -> void:
	var s: Dictionary = state()
	if int(s["day"]) != today:
		s["day"] = today
		s["used"] = int(s["used"]) + 1


## `bridge_man_start`: the acre he stands in today.
static func tortimer_block(layout: WorldData) -> Vector2i:
	var list: Array[Vector2i] = blocks(layout)
	if list.is_empty():
		return Vector2i(-1, -1)
	var s: Dictionary = state()
	if int(s["used"]) >= list.size():
		s["used"] = 0
	var remain: int = list.size() - 1 - int(s["used"])
	s["top"] = remain == 0
	return list[remain]


## "Here is good!": the bridge goes up in `block` tomorrow.
static func order(block: Vector2i, today: int) -> void:
	var s: Dictionary = state()
	s["pending"] = true
	s["build"] = today + 1
	s["bx"] = block.x
	s["bz"] = block.y


## `bridge_make_in`: from 6:00 on the build day (or any day after).
static func due_to_build(today: int, hour: int) -> bool:
	var s: Dictionary = state()
	if not bool(s["pending"]) or bool(s["exists"]):
		return false
	return today > int(s["build"]) or (today == int(s["build"]) and hour >= 6)


static func build_if_due(today: int, hour: int) -> bool:
	if not due_to_build(today, hour):
		return false
	state()["exists"] = true
	return true


## `aESC_owari_message`: the next of five "I'll look elsewhere" lines.
static func elsewhere_msg() -> int:
	var s: Dictionary = state()
	var n: int = int(s["msg_no"])
	s["msg_no"] = (n + 1) % 5
	return (MSG_ELSEWHERE_TOP if bool(s["top"]) else MSG_ELSEWHERE) + n


static func time_msg(hour: int) -> int:
	if hour < 6 or hour >= 23:
		return MSG_NIGHT
	if hour < 10:
		return MSG_MORNING
	if hour < 17:
		return MSG_DAY
	return MSG_EVENING


static func units(kind: int) -> Array[Vector3i]:
	return UNITS_A1 if kind == 1 else UNITS_A0


## `aBridgeA_set_BgOffset`: deck heights and wood-bridge attributes on the seven units.
static func apply_collision(layout: WorldData, grid: WorldGrid, spot: Vector3i) -> void:
	var centre := Vector2i(spot.x, spot.y)
	var centre_y: float = FieldCollision.height_at(layout, centre, false)
	for u: Vector3i in units(spot.z):
		var cell: Vector2i = centre + Vector2i(u.x, u.z)
		var row: Array = REWRITE[u.y]
		if u.y == 5 and is_equal_approx(FieldCollision.height_at(layout, cell, false), centre_y):
			row = REWRITE[0]
		FieldCollision.set_plus(cell, {"c": row[1], "nw": row[2], "sw": row[3], "se": row[4], "ne": row[5], "s": row[6]})
		FieldCollision.set_attr_override(cell, int(row[0]))
		## `_forbids_enter` reads the layout: the deck is a path now, not the river.
		if layout.is_in_bounds(cell):
			layout.set_terrain_cell(cell, WorldGrid.Terrain.PATH)
		if grid != null and grid.is_in_bounds(cell):
			grid.set_terrain(cell, WorldGrid.Terrain.PATH)
	FieldCollision.invalidate_segments()


## The bridge in place, when it stands.
static func restore(world: Node, layout: WorldData, grid: WorldGrid) -> Node3D:
	var s: Dictionary = state()
	if not bool(s["exists"]) or world == null or layout == null:
		return null
	var spot: Vector3i = spot_in(layout, Vector2i(int(s["bx"]), int(s["bz"])))
	if spot.x < 0:
		return null
	var centre := Vector2i(spot.x, spot.y)
	var y: float = FieldCollision.ground_y(layout, centre)
	apply_collision(layout, grid, spot)
	var objects: Node = world.get_node_or_null("Objects")
	if objects == null or not ResourceLoader.exists(SCENE):
		return null
	var host: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	host.set("kind", spot.z)
	host.add_to_group(GROUP)
	objects.add_child(host)
	var pos: Vector3 = grid.cell_to_world(centre) if grid != null else Vector3.ZERO
	pos.y = y + LIFT_GX * FieldCatalog.GX_TO_METERS
	host.global_position = pos
	host.rotation.y = deg_to_rad(-90.0) if spot.z == 1 else 0.0
	return host
