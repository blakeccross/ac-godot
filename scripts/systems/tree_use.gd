class_name TreeUse
extends RefCounted

## Chop / shake / stump / drop rules (`bg_item` `drop_fruit` + cut table).
## Not an autoload. The tree scene only presents the result.

enum Size { S0, S1, S2, FULL }
enum Stage { FRUITING, BARE, STUMP }
## Hidden contents on bare mature trees (`TREE_BELLS` / `TREE_BEES` / `TREE_FTR`
## and planted money denominations). Fruit uses `Stage.FRUITING` instead.
enum Content { NONE, BELLS, BEES, FURNITURE, MONEY_100, MONEY_1000, MONEY_10000, MONEY_30000 }

const DROP_OFFSETS: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]
## `fruit_set` crown offsets (GX) for standard drops / honeycomb / coconut.
const CROWN_GX: Array[Vector3] = [
	Vector3(-22.5, 65.0, 17.5),
	Vector3(22.5, 72.0, 12.5),
	Vector3(-2.5, 97.5, 7.5),
]
const CROWN_HONEY_GX: Array[Vector3] = [
	Vector3(-37.5, 65.0, 17.5),
	Vector3(37.5, 72.0, 12.5),
	Vector3(-2.5, 97.5, 7.5),
]
const CROWN_PALM_GX: Array[Vector3] = [
	Vector3(-10.0, 70.0, 2.5),
	Vector3(10.0, 75.0, 0.0),
]
## `drop_speed` frames at 30 Hz (`fruit_set`).
const DROP_SPEED_FRAMES: Array[int] = [14, 18, 22]
const HONEY_DROP_FRAMES := 5
const FURNITURE_DROP_FRAMES := 26
const GAME_FPS := 30.0

const MONEY_IDS: Dictionary = {
	Content.BELLS: &"money_100",
	Content.MONEY_100: &"money_100",
	Content.MONEY_1000: &"money_1000",
	Content.MONEY_10000: &"money_10000",
	Content.MONEY_30000: &"money_30000",
}

var size: Size = Size.FULL
var stage: Stage = Stage.BARE
var content: Content = Content.NONE
var hits_left: int = 3
var fruit_count: int = 0
var palm_fruit: bool = false
var fruit_item: ItemData = null


class Outcome:
	var dropped_fruit: int = 0
	var felled: bool = false
	var shook: bool = false
	var spawn_bees: bool = false
	## Items to emit (fruit, money bags, honeycomb, furniture). Empty when rustle-only.
	var drops: Array[ItemData] = []


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


static func content_from_id(id: StringName) -> Content:
	match id:
		&"bells":
			return Content.BELLS
		&"bees":
			return Content.BEES
		&"furniture":
			return Content.FURNITURE
		&"money_100":
			return Content.MONEY_100
		&"money_1000":
			return Content.MONEY_1000
		&"money_10000":
			return Content.MONEY_10000
		&"money_30000":
			return Content.MONEY_30000
		_:
			return Content.NONE


static func content_id(c: Content) -> StringName:
	match c:
		Content.BELLS:
			return &"bells"
		Content.BEES:
			return &"bees"
		Content.FURNITURE:
			return &"furniture"
		Content.MONEY_100:
			return &"money_100"
		Content.MONEY_1000:
			return &"money_1000"
		Content.MONEY_10000:
			return &"money_10000"
		Content.MONEY_30000:
			return &"money_30000"
		_:
			return &""


static func money_drop_count(c: Content) -> int:
	match c:
		Content.BELLS:
			return 1
		Content.MONEY_100, Content.MONEY_1000, Content.MONEY_10000, Content.MONEY_30000:
			return 3
		_:
			return 0


func configure(
	plant: PlantData,
	visual_id: StringName,
	as_stump: bool,
	p_size: Size = Size.FULL,
	fruit_ready: bool = true,
	p_content: Content = Content.NONE
) -> void:
	size = p_size
	hits_left = hits_for(size)
	palm_fruit = visual_id == &"TREE_PALM_FRUIT"
	fruit_item = plant.fruit if plant != null else null
	fruit_count = fruit_count_for(visual_id, plant) if fruit_ready else 0
	content = Content.NONE if fruit_count > 0 else p_content
	if as_stump:
		stage = Stage.STUMP
		hits_left = 0
		content = Content.NONE
	elif fruit_count > 0:
		stage = Stage.FRUITING
	else:
		stage = Stage.BARE


func sync_growth(
	plant: PlantData,
	visual_id: StringName,
	p_size: Size,
	fruit_ready: bool,
	p_content: Content = Content.NONE
) -> void:
	if stage == Stage.STUMP:
		return
	var size_changed: bool = size != p_size
	size = p_size
	if size_changed:
		hits_left = hits_for(size)
	palm_fruit = visual_id == &"TREE_PALM_FRUIT"
	fruit_item = plant.fruit if plant != null else null
	fruit_count = fruit_count_for(visual_id, plant) if fruit_ready else 0
	if fruit_count > 0:
		content = Content.NONE
		stage = Stage.FRUITING
	else:
		content = p_content
		stage = Stage.BARE


func shake() -> Outcome:
	var out := Outcome.new()
	if stage == Stage.STUMP:
		return out
	out.shook = true
	_apply_drops(out)
	return out


func chop() -> Outcome:
	var out := Outcome.new()
	if stage == Stage.STUMP or hits_left <= 0:
		return out
	_apply_drops(out)
	out.shook = true
	hits_left -= 1
	if hits_left <= 0:
		stage = Stage.STUMP
		content = Content.NONE
		out.felled = true
	return out


func _apply_drops(out: Outcome) -> void:
	if stage == Stage.FRUITING:
		out.dropped_fruit = fruit_count
		out.drops = _fruit_items(fruit_count)
		stage = Stage.BARE
		fruit_count = 0
		return
	match content:
		Content.BELLS, Content.MONEY_100, Content.MONEY_1000, Content.MONEY_10000, Content.MONEY_30000:
			var bag: ItemData = ItemCatalog.get_item(MONEY_IDS.get(content, &"money_100") as StringName)
			var n: int = money_drop_count(content)
			for _i: int in n:
				if bag != null:
					out.drops.append(bag)
		Content.BEES:
			var comb: ItemData = ItemCatalog.get_item(&"honeycomb")
			if comb != null:
				out.drops.append(comb)
			out.spawn_bees = true
		Content.FURNITURE:
			var ftr: ItemData = _random_furniture()
			if ftr != null:
				out.drops.append(ftr)
		_:
			pass
	content = Content.NONE


func _fruit_items(count: int) -> Array[ItemData]:
	var out: Array[ItemData] = []
	if fruit_item == null or count <= 0:
		return out
	for _i: int in count:
		out.append(fruit_item)
	return out


static func _random_furniture() -> ItemData:
	var picks: Array[FurnitureData] = []
	for item: ItemData in ItemCatalog.all_items():
		if item is FurnitureData:
			picks.append(item as FurnitureData)
	if picks.is_empty():
		return null
	return picks[randi() % picks.size()]


static func pick_drop_cells(
	origin: Vector2i, grid: WorldGrid, count: int, prefer_east: bool = false
) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if grid == null or count <= 0:
		return cells
	var order: Array[Vector2i] = DROP_OFFSETS.duplicate()
	if prefer_east and order.size() >= 2:
		## Single-item facing bias in `fruit_set`: start at East when tree is east of player.
		order = [DROP_OFFSETS[1], DROP_OFFSETS[0], DROP_OFFSETS[2]]
	for offset: Vector2i in order:
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


static func crown_offset(index: int, is_honey: bool, is_palm: bool) -> Vector3:
	var table: Array[Vector3] = CROWN_GX
	if is_honey:
		table = CROWN_HONEY_GX
	elif is_palm:
		table = CROWN_PALM_GX
	if table.is_empty():
		return Vector3(0.0, 3.0, 0.0)
	var i: int = clampi(index, 0, table.size() - 1)
	return table[i] * FieldCatalog.GX_TO_METERS


static func drop_duration(index: int, is_honey: bool, is_furniture: bool) -> float:
	if is_furniture:
		return float(FURNITURE_DROP_FRAMES) / GAME_FPS
	if is_honey:
		return float(HONEY_DROP_FRAMES) / GAME_FPS
	var frames: int = DROP_SPEED_FRAMES[clampi(index, 0, DROP_SPEED_FRAMES.size() - 1)]
	return float(frames) / GAME_FPS


static func _try_add_drop(cells: Array[Vector2i], grid: WorldGrid, cell: Vector2i) -> void:
	if cells.has(cell):
		return
	if not grid.can_place(cell, Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.ITEM):
		return
	cells.append(cell)
