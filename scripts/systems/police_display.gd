class_name PoliceDisplay
extends RefCounted

## Police box indoor layout (`SCENE_POLICE_BOX` / `FG_TYPE_POLICE_INDOOR` / `police_box_actable`).
## Behavioral reference: `police_box.c` scene, `bg_police_item`, `ac_npc_police2` (Booker).

## Walkable from `police_indoor` collision. Exit `EXIT_DOOR1` at (4,10)/(5,10).
const INNER_ORIGIN := Vector2i(1, 1)
const INNER_SIZE := Vector2i(8, 10)
const DOOR_CELL := Vector2i(4, 10)
const SPAWN_CELL := Vector2i(4, 9)

## `POLICE_BOX_player_data` GX {200,0,400}, face south (`yaw -32768`).
const SPAWN_GX := Vector3(200.0, 0.0, 400.0)
const SPAWN_FACING := WorldGrid.Facing.SOUTH

## `police_box_actable` ut (4,6) → GX center.
const BOOKER_STAND_UT := Vector2i(4, 6)
const BOOKER_STAND_GX := Vector3(180.0, 0.0, 260.0)
const BOOKER_FACING := WorldGrid.Facing.SOUTH
const BOOKER_SPECIES := &"plc"

## `FG_TYPE_POLICE_INDOOR` RSV_POLICE_ITEM_0..19 cells (row-major fill order).
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

const SHELL_ID := &"police_indoor"


static func gx_to_world(grid: WorldGrid, gx: Vector3) -> Vector3:
	return MuseumDisplay.gx_to_world(grid, gx)


static func cell_for_slot(slot: int) -> Vector2i:
	if slot < 0 or slot >= LOST_FOUND_CELLS.size():
		return Vector2i(-1, -1)
	return LOST_FOUND_CELLS[slot]
