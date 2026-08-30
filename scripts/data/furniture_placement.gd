class_name FurniturePlacement
extends Resource

## One furniture actor on a room's unit grid (`mRmTp_DIRECT_*` → `WorldGrid.Facing`).

@export var id: StringName = &""
@export var furniture_id: StringName = &""
@export var cell: Vector2i = Vector2i.ZERO
@export var facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
## Override catalog footprint when set (NPC FG TYPEA/B/C). Zero → use FurnitureData.
@export var footprint: Vector2i = Vector2i.ZERO
## Mannequin shirt (`iam_fmanekin` / `mPlib_Load_PlayerTexAndPallet`). −1 → none.
@export var cloth_index: int = -1
## 0 = floor / table; 1 = small item on a surface (`aFTR_SET_TYPE_ON_SURFACE`).
@export var layer: int = 0
## TV / stereo / gyroid switch (`switch_bit`).
@export var on: bool = true
## Drawer / wardrobe / stereo slots (`aFTR_KEEP_ITEM_COUNT`).
@export var stored: PackedStringArray = PackedStringArray()
## Fish, bug, umbrella, or shirt sitting on this actor.
@export var display_id: StringName = &""


func resolved_footprint(data: FurnitureData) -> Vector2i:
	if footprint != Vector2i.ZERO:
		return footprint
	if data != null:
		return data.resolved_footprint()
	return Vector2i.ONE


func to_save() -> Dictionary:
	var bag := {
		"id": String(id),
		"furniture_id": String(furniture_id),
		"x": cell.x,
		"z": cell.y,
		"facing": int(facing),
	}
	if footprint != Vector2i.ZERO:
		bag["fw"] = footprint.x
		bag["fd"] = footprint.y
	if cloth_index >= 0:
		bag["cl"] = cloth_index
	if layer > 0:
		bag["ly"] = layer
	if not on:
		bag["on"] = 0
	if not stored.is_empty():
		var rows: Array = []
		for item_id: String in stored:
			rows.append(item_id)
		bag["st"] = rows
	if display_id != &"":
		bag["di"] = String(display_id)
	return bag


static func from_save(data: Variant) -> FurniturePlacement:
	var placement := FurniturePlacement.new()
	if typeof(data) != TYPE_DICTIONARY:
		return placement
	var bag: Dictionary = data
	placement.id = StringName(str(bag.get("id", "")))
	placement.furniture_id = StringName(str(bag.get("furniture_id", "")))
	placement.cell = Vector2i(int(bag.get("x", 0)), int(bag.get("z", 0)))
	placement.facing = int(bag.get("facing", 0)) as WorldGrid.Facing
	if bag.has("fw") and bag.has("fd"):
		placement.footprint = Vector2i(int(bag.get("fw", 0)), int(bag.get("fd", 0)))
	if bag.has("cl"):
		placement.cloth_index = int(bag.get("cl", -1))
	placement.layer = int(bag.get("ly", 0))
	if bag.has("on"):
		placement.on = bool(bag.get("on", 1))
	var stored_raw: Variant = bag.get("st", [])
	if typeof(stored_raw) == TYPE_ARRAY:
		for row: Variant in stored_raw as Array:
			placement.stored.append(str(row))
	placement.display_id = StringName(str(bag.get("di", "")))
	return placement
