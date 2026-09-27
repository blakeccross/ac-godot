class_name PoliceDisplay
extends RefCounted

## Police box indoor layout (`SCENE_POLICE_BOX` / `FG_TYPE_POLICE_INDOOR` / `police_box_actable`).
## Behavioral reference: `police_box.c` scene, `bg_police_item`, `ac_npc_police2` (Booker),
## `ef_room_sunshine_police`.

## Walkable from `police_indoor` collision. Exit `EXIT_DOOR1` at (4,10)/(5,10).
const INNER_ORIGIN := Vector2i(1, 1)
const INNER_SIZE := Vector2i(8, 10)
const DOOR_CELL := Vector2i(4, 10)
const SPAWN_CELL := Vector2i(4, 9)

## Outdoor enter (`aPBOX_police_box_enter_data`): GX {200,0,380}, `mSc_DIRECT_NORTH`.
## Not scene `POLICE_BOX_player_data` {200,0,400} (that floors onto EXIT_DOOR1).
const SPAWN_GX := Vector3(200.0, 0.0, 380.0)
const SPAWN_FACING := WorldGrid.Facing.NORTH

## `police_box_actable` ut (4,6) → GX center.
const BOOKER_STAND_UT := Vector2i(4, 6)
const BOOKER_STAND_GX := Vector3(180.0, 0.0, 260.0)
const BOOKER_FACING := WorldGrid.Facing.SOUTH
## `SP_NPC_POLICE2` → `pla_1` (`plc_1` is outdoor Copper / `SP_NPC_POLICE`).
const BOOKER_SPECIES := &"pla"

## `FG_TYPE_POLICE_INDOOR` in `fgdata.bin`: the 16×16 unit template whose
## `RSV_POLICE_ITEM_0`…`_19` units are the lost-and-found slots.
const FG_TYPE_POLICE_INDOOR := 0x00CE
const RSV_POLICE_ITEM_0 := 0xF128
const EXIT_DOOR1 := 0x4081

## Fallback slot units when the disc FG catalog is not generated (row-major fill order).
const LOST_FOUND_CELLS: Array[Vector2i] = [
	Vector2i(1, 1),
	Vector2i(2, 1),
	Vector2i(3, 1),
	Vector2i(4, 1),
	Vector2i(5, 1),
	Vector2i(6, 1),
	Vector2i(7, 1),
	Vector2i(8, 1),
	Vector2i(2, 3),
	Vector2i(3, 3),
	Vector2i(4, 3),
	Vector2i(5, 3),
	Vector2i(6, 3),
	Vector2i(7, 3),
	Vector2i(2, 5),
	Vector2i(3, 5),
	Vector2i(4, 5),
	Vector2i(5, 5),
	Vector2i(6, 5),
	Vector2i(7, 5),
]

## `bPI_outPutData`: each kept item is its field card (`mNT_get_itemTableNo`) at the
## unit centre, on the floor, at `Matrix_scale(0.01)`.
const ITEM_UNIT_CENTER_GX := 20.0

## --- Booker (`ac_npc_police2`) -----------------------------------------------------------
## `aPOL2_get_zone`: unit z clamps to 2…6 (5 rows); unit x splits at 1 / 4 / 7 (4 columns).
const ZONE_COLUMNS := 4
const ZONE_ROWS := 5
## `aPOL2_search_player2` waypoint per zone column / row (GX).
const ZONE_POS_X: Array[float] = [60.0, 140.0, 260.0, 340.0]
const ZONE_POS_Z: Array[float] = [100.0, 140.0, 180.0, 220.0, 300.0]
## `aPOL2_decide_next_move_act` squared-distance gates (GX²).
const STOP_DIST_SQ := 50.0 * 50.0 - 50.0
const WALK_DIST_SQ := 70.0 * 70.0 + 100.0
## `aPOL2_search_player2`: close enough to a waypoint to pick the next zone.
const WAYPOINT_DIST_SQ := 14.0 * 14.0 + 4.0

## --- Window sunshine (`POLICE_BOX_actor_data` / `ef_room_sunshine_police`) ---------------
## Actor positions and `actor_specific` (2 = left window, 3 = right window).
const SUNSHINE_L_GX := Vector3(40.0, 0.0, 200.0)
const SUNSHINE_R_GX := Vector3(360.0, 0.0, 200.0)
const SUNSHINE_VISUAL := &"obj_koban_shine"

const SHELL_ID := &"police_indoor"
## `aHC_position_data` SCENE_POLICE_BOX: back-wall clock (`obj_clock_koban`). y is 0 —
## the skeleton carries the mounting height.
const CLOCK_GX := Vector3(200.0, 0.0, 30.0)
const CLOCK_VISUAL := &"obj_clock_koban"


static func gx_to_world(grid: WorldGrid, gx: Vector3) -> Vector3:
	return MuseumDisplay.gx_to_world(grid, gx)


static func cell_for_slot(slot: int) -> Vector2i:
	var cells: Array[Vector2i] = lost_found_cells()
	if slot < 0 or slot >= cells.size():
		return Vector2i(-1, -1)
	return cells[slot]


## Slot units read from `FG_TYPE_POLICE_INDOOR` when the FG catalog is generated.
static func lost_found_cells() -> Array[Vector2i]:
	var from_fg: Array[Vector2i] = cells_from_fg(FgCatalog.items(FG_TYPE_POLICE_INDOOR))
	return from_fg if not from_fg.is_empty() else LOST_FOUND_CELLS


## `RSV_POLICE_ITEM_N` → slot N. Empty unless all twenty are present.
static func cells_from_fg(items: PackedInt32Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if items.size() != FgCatalog.ITEMS_PER_ACRE:
		return out
	out.resize(PoliceBook.STORAGE_COUNT)
	var found := 0
	for i: int in items.size():
		var slot: int = items[i] - RSV_POLICE_ITEM_0
		if slot < 0 or slot >= PoliceBook.STORAGE_COUNT:
			continue
		out[slot] = Vector2i(i % 16, i / 16)
		found += 1
	if found != PoliceBook.STORAGE_COUNT:
		out.clear()
	return out


static func slot_for_cell(cell: Vector2i) -> int:
	return lost_found_cells().find(cell)


static func unit_center_gx(cell: Vector2i) -> Vector3:
	return Vector3(
		float(cell.x) * 40.0 + ITEM_UNIT_CENTER_GX, 0.0, float(cell.y) * 40.0 + ITEM_UNIT_CENTER_GX
	)


## `aPOL2_get_zone` on a GX position.
static func zone_for_gx(gx: Vector3) -> int:
	var ux: int = floori(gx.x / 40.0)
	var uz: int = clampi(floori(gx.z / 40.0), 2, 6)
	var zone: int = (uz - 2) * ZONE_COLUMNS
	if ux > 7:
		zone += 3
	elif ux > 4:
		zone += 2
	elif ux > 1:
		zone += 1
	return zone


static func zone_waypoint_gx(zone: int) -> Vector3:
	var zx: int = posmod(zone, ZONE_COLUMNS)
	var zz: int = clampi(zone / ZONE_COLUMNS, 0, ZONE_ROWS - 1)
	return Vector3(ZONE_POS_X[zx], 0.0, ZONE_POS_Z[zz])


## `aPOL2_get_next_zone`: the next zone Booker heads for on his way to `dst`.
## Rows 1 and 3 (units z 3 / 5) are the shelf rows. `coin` stands in for `RANDOM(2)`.
static func next_zone(dst: int, src: int, coin: int = 0) -> int:
	var src_z: int = src / ZONE_COLUMNS
	if src_z == 1 or src_z == 3:
		return _next_zone_sub0(dst, src, coin)
	return _next_zone_sub1(dst, src)


static func _next_zone_move_z(dst_x: int, dst_z: int, src_x: int, src_z: int) -> int:
	if src_x == 0 or src_x == 3:
		if src_z < dst_z:
			return src_x + (src_z + 1) * ZONE_COLUMNS
		return src_x + (src_z - 1) * ZONE_COLUMNS
	if src_x == dst_x:
		## Middle columns step out to the nearer side aisle.
		if src_x == 1:
			return src_x + src_z * ZONE_COLUMNS - 1
		return src_x + src_z * ZONE_COLUMNS + 1
	if src_x < dst_x:
		return src_x + src_z * ZONE_COLUMNS + 1
	return src_x + src_z * ZONE_COLUMNS - 1


static func _next_zone_sub0(dst: int, src: int, coin: int) -> int:
	var src_x: int = src % ZONE_COLUMNS
	var src_z: int = src / ZONE_COLUMNS
	var dst_x: int = dst % ZONE_COLUMNS
	var dst_z: int = dst / ZONE_COLUMNS
	if src_z != dst_z:
		return _next_zone_move_z(dst_x, dst_z, src_x, src_z)
	if src_x == dst_x:
		return dst
	return src_x + (src_z + (coin & 1)) * ZONE_COLUMNS


static func _next_zone_sub1(dst: int, src: int) -> int:
	var src_x: int = src % ZONE_COLUMNS
	var src_z: int = src / ZONE_COLUMNS
	var dst_x: int = dst % ZONE_COLUMNS
	var dst_z: int = dst / ZONE_COLUMNS
	if absi(dst_z - src_z) > 1:
		return _next_zone_move_z(dst_x, dst_z, src_x, src_z)
	if src_x == dst_x:
		return dst
	if src_x < dst_x:
		return src_x + src_z * ZONE_COLUMNS + 1
	return src_x + src_z * ZONE_COLUMNS - 1


## --- Sunshine timing (`calc_alpha_Ef_Room_SunshinePolice` / `_actor_move`) ---------------

## `Ef_Room_Sunshine_Police_actor_ct`: every non-zero `actor_specific` first steps −1 X,
## then case 2 nets −1 more and case 3 nets +1; Y sits 39 GX under the floor
## (`1 + BgY − 40`). The beam model rises from there through the window.
static func sunshine_anchor_gx(actor_gx: Vector3, left: bool) -> Vector3:
	var x: float = actor_gx.x - 1.0 + (-1.0 if left else 1.0)
	return Vector3(x, actor_gx.y + 1.0 - 40.0, actor_gx.z)


## Beam alpha 0–255 before `mKK_windowlight_alpha_get()`: fades in to 120 over the small
## hours, peaks at 255 at noon, rain/snow × 0.6.
static func sunshine_alpha(now_sec: int, raining: bool = false) -> int:
	var a: float
	if now_sec < 14400:
		a = 120.0 * (float(14400 - now_sec) / 14400.0)
	elif now_sec < 72000:
		a = 255.0 * (float(28800 - absi(now_sec - 43200)) / 28800.0)
	else:
		a = 120.0 * (float(14400 - (86400 - now_sec)) / 14400.0)
	if raining:
		a *= 0.6
	return int(a) & 0xFF


## `calc_scale_Ef_Room_Sunshine_Police`: `1.5 · sin(sec · 90° / span)` in units of the
## 0.01 model scale. `short` picks the 4-hour span, else 8 hours.
static func sunshine_scale(short: bool, sec: int) -> float:
	var span: float = 14400.0 if short else 28800.0
	return 1.5 * sin(float(sec) / span * PI * 0.5)


## X stretch of the left (west) window beam; 0 hides it. Night 00–04 and afternoon 12–20.
static func sunshine_left_x(now_sec: int) -> float:
	if now_sec < 14400:
		return sunshine_scale(true, now_sec)
	if now_sec >= 43200 and now_sec < 72000:
		return sunshine_scale(false, now_sec - 43200)
	return 0.0


## X stretch of the right (east) window beam, mirrored. Morning 04–12 and evening 20–24.
static func sunshine_right_x(now_sec: int) -> float:
	if now_sec >= 14400 and now_sec < 43200:
		return -sunshine_scale(false, 43200 - now_sec)
	if now_sec >= 72000:
		return -sunshine_scale(true, 86400 - now_sec)
	return 0.0


## `mEnv_MakeWindowLightAlpha` target for a room with no light switch (the police box):
## 1 from 05:00 to 18:00, else 0. It also drops to 0 for ±120 s around three marks the
## original compares through an `s16` cast of `now_sec` — midnight, noon, and (wrapped)
## 05:47:44 — so the beams blink off there too.
static func window_light_target(now_sec: int) -> float:
	for mark: int in [0, 86400, 43200]:
		if absi(_s16(now_sec - mark)) < 120:
			return 0.0
	if now_sec >= 5 * 3600 and now_sec < 18 * 3600:
		return 1.0
	return 0.0


## `add_calc(..., 0.5 * step, 0.5 * step)` with `step = 1/100`: 0.005 per 60 Hz frame.
const WINDOW_LIGHT_RATE := 0.005 * 60.0


static func _s16(v: int) -> int:
	var w: int = v & 0xFFFF
	return w - 0x10000 if w >= 0x8000 else w


## `setup_mode_Ef_Room_Sunshine_Police`: sun window colour 04:00–20:00, else moon.
static func sunshine_uses_sun(now_sec: int) -> bool:
	return now_sec >= 14400 and now_sec < 72000


## Units of the `police_indoor` BG that block inside the room: `Vector2i` unit → height
## above the floor in GX. Shelves (20 GX), phone desk, locker, and the wall either side of
## the entrance strip. Empty when the pipeline's `.col.json` is not generated.
static func blocked_units() -> Dictionary:
	return InteriorUnitCollision.blocked_from_bg(
		SHELL_ID, FieldCatalog.LAND_COUNTS, FieldCatalog.HEIGHT_MAX, Rect2i(INNER_ORIGIN, INNER_SIZE)
	)
