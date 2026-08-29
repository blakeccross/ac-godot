class_name TreeUse
extends RefCounted

## Chop / shake / stump rules. Not an autoload. The tree scene only presents the result.

enum Size { S0, S1, S2, FULL }
enum Stage { FRUITING, BARE, STUMP }

const DROP_OFFSETS: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]

var size: Size = Size.FULL
var stage: Stage = Stage.BARE
var hits_left: int = 3
var fruit_count: int = 0


class Outcome:
	var dropped_fruit: int = 0
	var felled: bool = false
	var shook: bool = false


static func hits_for(p_size: Size) -> int:
	match p_size:
		Size.S0:
			return 1
		Size.S1:
			return 2
		_:
			return 3


static func size_for(_visual_id: StringName) -> Size:
	return Size.FULL


static func fruit_count_for(visual_id: StringName, plant: PlantData) -> int:
	if plant == null or plant.fruit == null:
		return 0
	if visual_id == &"TREE_PALM_FRUIT":
		return 2
	return 3


func configure(
	plant: PlantData,
	visual_id: StringName,
	as_stump: bool,
	p_size: Size = Size.FULL,
	fruit_ready: bool = true
) -> void:
	size = p_size
	hits_left = hits_for(size)
	fruit_count = fruit_count_for(visual_id, plant) if fruit_ready else 0
	if as_stump:
		stage = Stage.STUMP
		hits_left = 0
	elif fruit_count > 0:
		stage = Stage.FRUITING
	else:
		stage = Stage.BARE


func sync_growth(
	plant: PlantData, visual_id: StringName, p_size: Size, fruit_ready: bool
) -> void:
	if stage == Stage.STUMP:
		return
	var size_changed: bool = size != p_size
	size = p_size
	if size_changed:
		hits_left = hits_for(size)
	fruit_count = fruit_count_for(visual_id, plant) if fruit_ready else 0
	stage = Stage.FRUITING if fruit_count > 0 else Stage.BARE


func shake() -> Outcome:
	var out := Outcome.new()
	if stage == Stage.STUMP:
		return out
	out.shook = true
	out.dropped_fruit = _take_fruit()
	return out


func chop() -> Outcome:
	var out := Outcome.new()
	if stage == Stage.STUMP or hits_left <= 0:
		return out
	out.dropped_fruit = _take_fruit()
	out.shook = true
	hits_left -= 1
	if hits_left <= 0:
		stage = Stage.STUMP
		out.felled = true
	return out


func _take_fruit() -> int:
	if stage != Stage.FRUITING:
		return 0
	stage = Stage.BARE
	return fruit_count


static func pick_drop_cells(origin: Vector2i, grid: WorldGrid, count: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if grid == null or count <= 0:
		return cells
	for offset: Vector2i in DROP_OFFSETS:
		if cells.size() >= count:
			break
		_try_add_drop(cells, grid, origin + offset)
	if cells.size() >= count:
		return cells
	for neighbor: Vector2i in grid.neighbors8(origin):
		if cells.size() >= count:
			break
		_try_add_drop(cells, grid, neighbor)
	return cells


static func _try_add_drop(cells: Array[Vector2i], grid: WorldGrid, cell: Vector2i) -> void:
	if cells.has(cell):
		return
	if not grid.can_place(cell, Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.ITEM):
		return
	cells.append(cell)
