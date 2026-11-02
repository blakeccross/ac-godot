class_name IslandRoute
extends RefCounted

## Kapp'n's boat route (`aBT_chk_point`, `ac_boat.c`): eight way-points from the town wharf (F-5)
## down to the island landing (H-5), in the decomp's field GX. The town world holds the
## sea they sail across; the island world holds the landing.

const CHECK_POINTS_GX: Array[Vector2] = [
	Vector2(3420.0, 4260.0), Vector2(3380.0, 4300.0), Vector2(3340.0, 4380.0), Vector2(3340.0, 4620.0),
	Vector2(3740.0, 4980.0), Vector2(3740.0, 5220.0), Vector2(3700.0, 5300.0), Vector2(3660.0, 5340.0),
]
const LAST := 7
## The town grid's first unit is the FG block (1, 1), at 640 GX; the island grid's is the left island
## block (4, 8), at (2560, 5120). 40 GX is one 2 m unit.
const TOWN_ORIGIN_GX := Vector2(640.0, 640.0)
const ISLAND_ORIGIN_GX := Vector2(2560.0, 5120.0)
const METERS_PER_GX := 0.05
## The boat cruises at 0.625 GX a tick (`aBT_calc_speed`).
const CRUISE := 0.625 * 60.0 * METERS_PER_GX
## `aBT_init_angleY`: moored at the wharf it points -45°, at the landing 135°.
const WHARF_YAW := deg_to_rad(-45.0)
const LANDING_YAW := deg_to_rad(135.0)
## The wharf acre: block (5, 6) holds `T_PORT`.
const WHARF_BLOCK := Vector2i(5, 6)


## Way-point `index` in metres from the grid's first-unit corner.
static func point(index: int, island: bool) -> Vector3:
	var gx: Vector2 = CHECK_POINTS_GX[clampi(index, 0, LAST)] - (ISLAND_ORIGIN_GX if island else TOWN_ORIGIN_GX)
	return Vector3(gx.x, 0.0, gx.y) * METERS_PER_GX


## The way-points a trip sails, in order of travel, from the town (out) or the landing (back).
static func path(out: bool) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	var indices: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]
	if not out:
		indices.reverse()
	for i: int in indices:
		pts.append(point(i, false))
	return pts


## True when the generated town has the wharf acre, so a boat waits there.
static func town_has_wharf(data: WorldData) -> bool:
	if data == null or data.acre_types.size() != TownFieldGenerator.BLOCK_TOTAL:
		return false
	var index: int = WHARF_BLOCK.y * TownFieldGenerator.BLOCK_X + WHARF_BLOCK.x
	return int(data.acre_types[index]) == TownFieldGenerator.T_PORT
