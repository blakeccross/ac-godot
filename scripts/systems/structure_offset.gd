class_name StructureOffset
extends RefCounted

## Structure walk collision is a heightfield rewrite (`mCoBG_SetPluss5PointOffset`),
## not a 3D box. Tables from `aMHS` / `aHUS` / `aMsm` / `aNW` / `aPBOX` /
## `aSHOP` / `aPOFF` set_bgOffset.

## Sentinel 11 in `aMHS` → small-house body offset (`height_dt[0]`).
const SMALL_BODY := 11
const NPC_BODY := 7
## `aMHS` `addX` / `addZ` as unit steps (216 s8 → −1; 90 GX still `Wpos2UtNum`s to +2).
const _WEST_X: Array[int] = [-1, 0, 1, 2]
const _EAST_X: Array[int] = [-2, -1, 0, 1]
const _Z: Array[int] = [2, 1, 0, -1]
const _NPC_X: Array[int] = [-1, 0, 1]
const _NPC_Z: Array[int] = [1, 0, -1]
## Able Sisters (`aNW`): addX {−80,−40,0,40}, addZ {80,40,0,−40}.
const _ABLE_X: Array[int] = [-2, -1, 0, 1]
const _ABLE_Z: Array[int] = [2, 1, 0, -1]
## Police box (`aPBOX`): addX {−40,0,40}, addZ {40,0,−40}.
const _POLICE_X: Array[int] = [-1, 0, 1]
const _POLICE_Z: Array[int] = [1, 0, -1]
## Museum (`aMsm`): unit_offset X −3..3, Z −2..2.
const _MUSEUM_X0 := -3
const _MUSEUM_X1 := 3
const _MUSEUM_Z0 := -2
const _MUSEUM_Z1 := 2
const MUSEUM_BODY := 10
const POLICE_BODY := 10


static func apply(data: WorldData) -> void:
	FieldCollision.clear_plus()
	if data == null:
		return
	for b: BuildingPlacement in data.buildings:
		if b == null:
			continue
		if HostCollision.is_player_house(b.visual_id) or String(b.id).begins_with("player_house"):
			_apply_player(data, b)
		elif HostCollision.is_museum(b.visual_id) or b.id == &"museum":
			_apply_museum(data, b)
		elif HostCollision.is_able_sisters(b.visual_id) or b.id == &"able_sisters":
			_apply_4x4_open_corners(data, shop_home_cell(b), _ABLE_TBL)
		elif HostCollision.is_post_office(b.visual_id) or b.id == &"post_office":
			## `aPOFF_set_bgOffset` matches Able Sisters' table.
			_apply_4x4_open_corners(data, shop_home_cell(b), _ABLE_TBL)
		elif HostCollision.is_shop(b.visual_id) or b.kind == &"shop" or b.id == &"acre_shop":
			_apply_4x4_open_corners(data, shop_home_cell(b), _SHOP_TBL)
		elif HostCollision.is_police(b.visual_id) or b.id == &"police":
			_apply_police(data, b)
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


static func museum_home_cell(placement: BuildingPlacement) -> Vector2i:
	## FG unit; occupancy NW is the same cell (`nw_off` 0).
	return placement.cell


static func able_home_cell(placement: BuildingPlacement) -> Vector2i:
	## FG unit; occupancy NW is FG+(−1,0) — same as east player house / shop.
	return shop_home_cell(placement)


static func shop_home_cell(placement: BuildingPlacement) -> Vector2i:
	## FG unit for shop / post / Able (`nw_off` −1,0).
	return placement.cell + Vector2i(1, 0)


static func police_home_cell(placement: BuildingPlacement) -> Vector2i:
	## FG unit at the center of the 3×3 (`nw_off` −1,−1).
	return npc_home_cell(placement)


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


static func _apply_museum(data: WorldData, placement: BuildingPlacement) -> void:
	## `aMsm_set_bgOffset`: every cell in the 7×5 gets offset 10 (no porch gap).
	var home: Vector2i = museum_home_cell(placement)
	var body := {"c": MUSEUM_BODY, "nw": MUSEUM_BODY, "sw": MUSEUM_BODY, "se": MUSEUM_BODY, "ne": MUSEUM_BODY, "s": 0}
	for oz: int in range(_MUSEUM_Z0, _MUSEUM_Z1 + 1):
		for ox: int in range(_MUSEUM_X0, _MUSEUM_X1 + 1):
			var cell := Vector2i(home.x + ox, home.y + oz)
			if not data.is_in_bounds(cell):
				continue
			FieldCollision.set_plus(cell, body.duplicate())


static func _apply_4x4_open_corners(data: WorldData, home: Vector2i, tbl: Array) -> void:
	## Shop / post / Able: 4×4 around home; corners (0,3,12,15) are skipped.
	for zi: int in 4:
		for xi: int in 4:
			var idx: int = zi * 4 + xi
			if idx == 0 or idx == 3 or idx == 12 or idx == 15:
				continue
			var cell := Vector2i(home.x + _ABLE_X[xi], home.y + _ABLE_Z[zi])
			if not data.is_in_bounds(cell):
				continue
			var row: Array = tbl[idx]
			FieldCollision.set_plus(cell, _row(row, 11))


static func _apply_police(data: WorldData, placement: BuildingPlacement) -> void:
	## `aPBOX_set_bgOffset`: 3×3 around home; door stand is SE outside the block.
	var home: Vector2i = police_home_cell(placement)
	for zi: int in 3:
		for xi: int in 3:
			var cell := Vector2i(home.x + _POLICE_X[xi], home.y + _POLICE_Z[zi])
			if not data.is_in_bounds(cell):
				continue
			var row: Array = _POLICE_TBL[zi * 3 + xi]
			FieldCollision.set_plus(cell, _row(row, POLICE_BODY))


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
## `aNW_set_bgOffset` / `aPOFF_set_bgOffset` (south→north; corners skipped at apply time).
const _ABLE_TBL: Array = [
	[0, 0, 0, 0, 0, 0],
	[13, 13, 0, 13, 13, 1],
	[13, 13, 13, 0, 13, 1],
	[0, 0, 0, 0, 0, 0],
	[13, 13, 0, 13, 13, 1],
	[13, 13, 13, 13, 14, 0],
	[13, 14, 13, 13, 13, 0],
	[13, 13, 13, 0, 13, 1],
	[13, 0, 13, 13, 13, 1],
	[13, 13, 13, 14, 13, 0],
	[13, 13, 14, 13, 13, 0],
	[13, 13, 13, 13, 0, 1],
	[0, 0, 0, 0, 0, 0],
	[13, 0, 13, 13, 13, 1],
	[13, 13, 13, 13, 0, 1],
	[0, 0, 0, 0, 0, 0],
]
## `aSHOP_set_bgOffset` height_table_ct (body 12; corners skipped).
const _SHOP_TBL: Array = [
	[0, 0, 0, 0, 0, 0],
	[12, 12, 0, 12, 12, 1],
	[12, 12, 12, 0, 12, 1],
	[0, 0, 0, 0, 0, 0],
	[12, 12, 0, 12, 12, 1],
	[12, 12, 12, 12, 12, 0],
	[12, 12, 12, 12, 12, 0],
	[12, 12, 12, 0, 12, 1],
	[12, 0, 12, 12, 12, 1],
	[12, 12, 12, 12, 12, 0],
	[12, 12, 12, 12, 12, 0],
	[12, 12, 12, 12, 0, 1],
	[0, 0, 0, 0, 0, 0],
	[12, 0, 12, 12, 12, 1],
	[12, 12, 12, 12, 0, 1],
	[0, 0, 0, 0, 0, 0],
]
## `aPBOX_set_bgOffset` height_table_ct (south→north).
const _POLICE_TBL: Array = [
	[10, 10, 0, 10, 10, 1],
	[10, 10, 10, 10, 10, 0],
	[10, 10, 10, 0, 10, 1],
	[10, 10, 10, 10, 10, 0],
	[10, 10, 10, 10, 10, 0],
	[10, 10, 10, 10, 10, 0],
	[10, 0, 10, 10, 10, 1],
	[10, 10, 10, 10, 10, 0],
	[10, 10, 10, 10, 0, 1],
]
