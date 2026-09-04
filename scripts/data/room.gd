class_name Room
extends Resource

## One indoor field. Same 16×16 unit grid as outdoor (`UT_X_NUM`). Wall and
## carpet are room fields, not furniture actors.

enum Kind {
	PLAYER,
	NPC,
	SHOP,
	BROKER,
	POST_OFFICE,
	POLICE,
	DUMP,
	KAMAKURA,
	MUSEUM,
	NEEDLEWORK,
	LIGHTHOUSE,
	TENT,
	COTTAGE,
}

@export var id: StringName = &""
@export var kind: Kind = Kind.PLAYER
@export var display_name: String = "Room"
@export var columns: int = 16
@export var rows: int = 16
@export var inner_origin: Vector2i = Vector2i(5, 5)
@export var inner_size: Vector2i = Vector2i(6, 6)
@export var door_cell: Vector2i = Vector2i(7, 10)
@export var spawn_cell: Vector2i = Vector2i(7, 9)
@export var wall_id: StringName = &"wall_default"
@export var floor_id: StringName = &"floor_default"
## Pipeline GLB prefixes (`room01`, `rom_myhome1_floor`, …). Empty → placeholder boxes.
@export var shell_ids: PackedStringArray = PackedStringArray()
@export var placements: Array[FurniturePlacement] = []
@export var can_decorate: bool = false
@export var open_hour: int = -1
@export var close_hour: int = -1
@export var linked_rooms: Array[StringName] = []
@export var parent_room_id: StringName = &""
@export var placement_seq: int = 0


func is_always_open() -> bool:
	return open_hour < 0 or close_hour < 0


func is_inner(cell: Vector2i) -> bool:
	return (
		cell.x >= inner_origin.x
		and cell.y >= inner_origin.y
		and cell.x < inner_origin.x + maxi(inner_size.x, 1)
		and cell.y < inner_origin.y + maxi(inner_size.y, 1)
	)


## House / shop EXIT_DOOR is a two-unit south strip (`door_cell`, `door_cell+(1,0)`).
func is_exit_cell(cell: Vector2i) -> bool:
	return cell == door_cell or cell == door_cell + Vector2i(1, 0)


func next_placement_id() -> StringName:
	placement_seq += 1
	return StringName("ftr_%d" % placement_seq)


func placement_by_id(placement_id: StringName) -> FurniturePlacement:
	if placement_id == &"":
		return null
	for entry: FurniturePlacement in placements:
		if entry != null and entry.id == placement_id:
			return entry
	return null


func to_save() -> Dictionary:
	var items: Array = []
	for entry: FurniturePlacement in placements:
		if entry != null and entry.furniture_id != &"":
			items.append(entry.to_save())
	var links: Array = []
	for room_id: StringName in linked_rooms:
		links.append(String(room_id))
	return {
		"id": String(id),
		"wall_id": String(wall_id),
		"floor_id": String(floor_id),
		"placements": items,
		"placement_seq": placement_seq,
		"linked_rooms": links,
		"parent_room_id": String(parent_room_id),
	}


func apply_runtime(data: Variant) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	var bag: Dictionary = data
	wall_id = StringName(str(bag.get("wall_id", String(wall_id))))
	floor_id = StringName(str(bag.get("floor_id", String(floor_id))))
	placement_seq = int(bag.get("placement_seq", placement_seq))
	var parent_raw: String = str(bag.get("parent_room_id", String(parent_room_id)))
	if parent_raw != "":
		parent_room_id = StringName(parent_raw)
	placements.clear()
	var items: Variant = bag.get("placements", [])
	if typeof(items) == TYPE_ARRAY:
		for row: Variant in items:
			var entry: FurniturePlacement = FurniturePlacement.from_save(row)
			if entry.furniture_id != &"":
				placements.append(entry)
