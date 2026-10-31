class_name PoorGround
extends RefCounted

## Poor ground (`mCoBG_Change2PoorAttr`): grass and soil units turned to the attribute that keeps
## trees from living on them. Three places get it when a field is made (`mFM_FieldInit`):
## the outer column of the left and right acres (`mFM_PoorTree`), four units under the
## player-house acre's north edge (`mFM_PoorTreeUnderPlayerBlock`), and the openings where
## acres meet (`mRF_CheckBeastRoad`, `data/world/acre_gates.json`), so planting never closes
## the way villagers cross. Not an autoload.

const GATES_PATH := "res://data/world/acre_gates.json"
## `mCoBG_ATTRIBUTE_GRASS0/1` → `GRASS2`, `SOIL0/1` → `SOIL2` (`mCoBG_Change2PoorAttr`).
const POOR_ATTR := {0: 2, 1: 2, 4: 6, 5: 6}
## `mFM_PoorTreeUnderPlayerBlock`: units (x, z) of acre C-3 (block 3, 3).
const HOUSE_BLOCK := Vector2i(3, 3)
const HOUSE_UNITS: Array[Vector2i] = [Vector2i(7, 0), Vector2i(8, 0), Vector2i(7, 1), Vector2i(8, 1)]

static var _gates: Dictionary = {}


## Every playable unit the field turns poor, in the order the decomp does it.
static func cells(data: WorldData) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if data == null or data.acre_types.size() != TownFieldGenerator.BLOCK_TOTAL:
		return out
	var last_column: int = WorldGenerator.FG_X * WorldGenerator.UT - 1
	for z: int in WorldGenerator.FG_Z * WorldGenerator.UT:
		out.append(Vector2i(0, z))
		out.append(Vector2i(last_column, z))
	var gates: Dictionary = _gate_table()
	var kinds: Array = gates.get("gate_kinds", [])
	var rows: Array = gates.get("block_gates", [])
	for bz: int in range(1, 1 + WorldGenerator.FG_Z):
		for bx: int in range(1, 1 + WorldGenerator.FG_X):
			var decomp_type: int = TownMap.decomp_block_type(int(data.acre_types[bz * TownFieldGenerator.BLOCK_X + bx]))
			if decomp_type < 0 or decomp_type >= rows.size():
				continue
			var origin: Vector2i = Vector2i((bx - 1) * WorldGenerator.UT, (bz - 1) * WorldGenerator.UT)
			var sides: Array = rows[decomp_type]
			for side: int in sides.size():
				for pair: Array in (kinds[int(sides[side])] as Array)[side]:
					for unit: Array in pair:
						out.append(origin + Vector2i(int(unit[0]), int(unit[1])))
	var house: Vector2i = Vector2i((HOUSE_BLOCK.x - 1) * WorldGenerator.UT, (HOUSE_BLOCK.y - 1) * WorldGenerator.UT)
	for unit: Vector2i in HOUSE_UNITS:
		out.append(house + unit)
	return out


## Write the poor attribute over `data`'s units (a field made anew, after `FieldCollision.reset`).
static func apply(data: WorldData) -> void:
	for cell: Vector2i in cells(data):
		var attr: int = FieldCollision.unit_attr_at_cell(data, cell)
		if POOR_ATTR.has(attr):
			FieldCollision.set_attr_override(data, cell, int(POOR_ATTR[attr]))


static func _gate_table() -> Dictionary:
	if _gates.is_empty():
		var file := FileAccess.open(GATES_PATH, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				_gates = parsed as Dictionary
	return _gates
