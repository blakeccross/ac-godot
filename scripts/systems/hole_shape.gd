class_name HoleShape
extends RefCounted

## Which hole mesh a dug unit shows (`mCoBG_GetHoleNumber_ClData`): the unit's centre and four
## corner heights, less their lowest, must match one row of `mCoBG_hole_data` exactly. Row n
## is `HOLEnn` / `obj_holen`, a mesh with that slope already built in (the hole is never
## rotated). No match (or a slate unit): no hole entry, though the dig still plays.

## `{c, nw, sw, se, ne}` in 10 GX counts (`top_left` = nw, `bot_left` = sw, …).
const PATTERNS: Array[PackedInt32Array] = [
	[0, 0, 0, 0, 0],
	[1, 2, 0, 0, 2],
	[1, 0, 2, 2, 0],
	[1, 0, 0, 2, 2],
	[1, 2, 2, 0, 0],
	[2, 2, 0, 2, 4],
	[2, 4, 2, 0, 2],
	[2, 0, 2, 4, 2],
	[2, 2, 4, 2, 0],
	[2, 2, 0, 2, 2],
	[2, 2, 2, 0, 2],
	[2, 0, 2, 2, 2],
	[2, 2, 2, 2, 0],
	[0, 0, 0, 0, 2],
	[0, 2, 0, 0, 0],
	[0, 0, 0, 2, 0],
	[0, 0, 2, 0, 0],
	[1, 0, 0, 0, 2],
	[1, 2, 0, 0, 0],
	[1, 0, 0, 2, 0],
	[1, 0, 2, 0, 0],
	[1, 2, 2, 0, 2],
	[1, 2, 0, 2, 2],
	[1, 2, 2, 2, 0],
	[1, 0, 2, 2, 2],
]


## Row for a unit's height counts (`{c, nw, sw, se, ne, s}`), or -1.
static func number_for_counts(unit: Dictionary) -> int:
	if int(unit.get("s", 0)) != 0:
		return -1
	var heights := PackedInt32Array([
		int(unit.get("c", 0)),
		int(unit.get("nw", 0)),
		int(unit.get("sw", 0)),
		int(unit.get("se", 0)),
		int(unit.get("ne", 0)),
	])
	var low: int = heights[0]
	for h: int in heights:
		low = mini(low, h)
	for i: int in heights.size():
		heights[i] -= low
	for n: int in PATTERNS.size():
		if PATTERNS[n] == heights:
			return n
	return -1


## Row for the field unit at `cell`. A unit with no collision table (placeholder acres) is flat.
static func number_for(data: WorldData, cell: Vector2i) -> int:
	var unit: Dictionary = FieldCollision.unit_counts(data, cell)
	if unit.is_empty():
		return 0
	return number_for_counts(unit)


static func visual_for(number: int) -> StringName:
	return StringName("HOLE%02d" % maxi(number, 0))
