class_name StructureOffset
extends RefCounted

## Structure walk collision is a heightfield rewrite (`mCoBG_SetPluss5PointOffset`),
## not a 3D box. Tables from `aMHS_set_bgOffset` / `aHUS_set_bgOffset`.

## Sentinel 11 in `aMHS` → small-house body offset (`height_dt[0]`).
const SMALL_BODY := 11
const NPC_BODY := 7
## `aMHS` `addX` / `addZ` as unit steps (216 s8 → −1; 90 GX still `Wpos2UtNum`s to +2).
const _WEST_X: Array[int] = [-1, 0, 1, 2]
const _EAST_X: Array[int] = [-2, -1, 0, 1]
const _Z: Array[int] = [2, 1, 0, -1]
const _NPC_X: Array[int] = [-1, 0, 1]
const _NPC_Z: Array[int] = [1, 0, -1]


static func apply(data: WorldData) -> void:
	FieldCollision.clear_plus()
	if data == null:
		return
	for b: BuildingPlacement in data.buildings:
		if b == null:
			continue
		if HostCollision.is_player_house(b.visual_id) or String(b.id).begins_with("player_house"):
			_apply_player(data, b)
		elif b.kind == &"house":
			_apply_npc(data, b)
	FieldCollision.invalidate_segments()


static func player_home_cell(placement: BuildingPlacement) -> Vector2i:
	## FG unit (`actor.home`), not the mesh shift. West occupancy NW is FG; east is FG+(−1,0).
	if placement.mesh_facing == WorldGrid.Facing.WEST:
		return placement.cell
	return placement.cell + Vector2i(1, 0)


static func npc_home_cell(placement: BuildingPlacement) -> Vector2i:
	## SIGN unit: center of the 3×3 (`aHUS` home).
	return Vector2i(
		placement.cell.x + placement.footprint.x / 2, placement.cell.y + placement.footprint.y / 2
	)


static func _apply_player(data: WorldData, placement: BuildingPlacement) -> void:
	var home: Vector2i = player_home_cell(placement)
	var west: bool = placement.mesh_facing == WorldGrid.Facing.WEST
	var xs: Array[int] = _WEST_X if west else _EAST_X
	var tbl: Array = _WEST_TBL if west else _EAST_TBL
	for zi: int in 4:
		for xi: int in 4:
			var cell := Vector2i(home.x + xs[xi], home.y + _Z[zi])
			if not data.is_in_bounds(cell):
				continue
			var row: Array = tbl[zi * 4 + xi]
			FieldCollision.set_plus(cell, _row(row, SMALL_BODY))


static func _apply_npc(data: WorldData, placement: BuildingPlacement) -> void:
	var home: Vector2i = npc_home_cell(placement)
	for zi: int in 3:
		for xi: int in 3:
			var cell := Vector2i(home.x + _NPC_X[xi], home.y + _NPC_Z[zi])
			if not data.is_in_bounds(cell):
				continue
			var row: Array = _NPC_TBL[zi * 3 + xi]
			FieldCollision.set_plus(cell, _row(row, NPC_BODY))


static func _row(row: Array, body: int) -> Dictionary:
	## height_tbl: CR, LU, LD, RD, RU, shape. 11 → body offset.
	var c: int = _ofs(int(row[0]), body)
	var nw: int = _ofs(int(row[1]), body)
	var sw: int = _ofs(int(row[2]), body)
	var se: int = _ofs(int(row[3]), body)
	var ne: int = _ofs(int(row[4]), body)
	return {"c": c, "nw": nw, "sw": sw, "se": se, "ne": ne, "s": int(row[5])}


static func _ofs(v: int, body: int) -> int:
	return body if v == 11 else v


## `side_idx == 0` (HOUSE0/2). Source comment labels this block "East".
const _WEST_TBL: Array = [
	[4, 4, 4, 4, 4, 0],
	[4, 4, 4, 0, 4, 1],
	[0, 0, 0, 0, 0, 0],
	[0, 0, 0, 0, 0, 0],
	[11, 11, 4, 11, 11, 1],
	[11, 11, 11, 11, 11, 0],
	[11, 11, 11, 0, 11, 1],
	[0, 0, 0, 0, 0, 0],
	[11, 4, 11, 11, 11, 1],
	[11, 11, 11, 11, 11, 0],
	[11, 11, 11, 11, 11, 0],
	[4, 4, 4, 0, 4, 1],
	[4, 4, 4, 4, 4, 0],
	[11, 4, 11, 11, 11, 1],
	[11, 11, 11, 11, 4, 1],
	[4, 4, 4, 4, 4, 0],
]
## `side_idx == 1` (HOUSE1/3).
const _EAST_TBL: Array = [
	[0, 0, 0, 0, 0, 0],
	[0, 0, 0, 0, 0, 0],
	[4, 4, 0, 4, 4, 1],
	[4, 4, 4, 4, 4, 0],
	[0, 0, 0, 0, 0, 0],
	[11, 11, 0, 11, 11, 1],
	[11, 11, 11, 11, 11, 0],
	[11, 11, 11, 4, 11, 1],
	[4, 4, 0, 4, 4, 1],
	[11, 11, 11, 11, 11, 0],
	[11, 11, 11, 11, 11, 0],
	[11, 11, 11, 11, 4, 1],
	[4, 4, 4, 4, 4, 0],
	[11, 4, 11, 11, 11, 1],
	[11, 11, 11, 11, 4, 1],
	[4, 4, 4, 4, 4, 0],
]
const _NPC_TBL: Array = [
	[7, 7, 7, 7, 7, 0],
	[0, 0, 0, 0, 0, 0],
	[7, 7, 7, 7, 7, 0],
	[7, 7, 7, 7, 7, 0],
	[7, 7, 7, 7, 7, 0],
	[7, 7, 7, 7, 7, 0],
	[7, 7, 7, 7, 7, 0],
	[7, 7, 7, 7, 7, 0],
	[7, 7, 7, 7, 7, 0],
]
