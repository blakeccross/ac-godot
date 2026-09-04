class_name ShopDisplay
extends RefCounted

## Nook's Cranny FG layout (`FG_TYPE_ROM_SHOP1` / template 0x22) and Tom Nook stand.
## Behavioral reference: `ac_shop_design`, `shop01_actable`, `aSI_wall/floor_default_table`.

## `aSI_*_default_table` → `WALL_SHOP*` / `FLOOR_SHOP*` (ETC bank = index 67+).
const NOOK_WALL_IDS: Array[StringName] = [&"wall_67", &"wall_68", &"wall_69", &"wall_68"]
const NOOK_FLOOR_IDS: Array[StringName] = [&"floor_67", &"floor_68", &"floor_69", &"floor_70"]

## Cranny walkable NW + size; exit `EXIT_DOOR1` at (3,8)/(4,8).
const CRANNY_INNER_ORIGIN := Vector2i(1, 1)
const CRANNY_INNER_SIZE := Vector2i(7, 8)
const CRANNY_DOOR_CELL := Vector2i(3, 8)
const CRANNY_SPAWN_CELL := Vector2i(3, 7)

## `shop0N_actable` stand ut → GX center (`ut * 40 + 20`).
## Cranny (3,5) · Nook 'n' Go (7,5) · Nookway (8,9) · Nookington's (7,11).
const NOOK_STAND_UT: Array[Vector2i] = [
	Vector2i(3, 5), Vector2i(7, 5), Vector2i(8, 9), Vector2i(7, 11)
]
const NOOK_STAND_GX := Vector3(140.0, 0.0, 220.0)
const NOOK_FACING := WorldGrid.Facing.SOUTH
## Permanent SPNPC leaves `cloth_idx` NONE (`aNPC_actor_init_for_special`). `0x205` on
## `l_sp_actor_name` is the name string, not a shirt — do not paint cloth onto eyes.
## Draw rows: SHOP_MASTER `rcn_1`, CONV `rcc_1`, SUPER `rcs_1`, DEPART `rcd_1`.
const NOOK_SPECIES_IDS: Array[StringName] = [&"rcn", &"rcc", &"rcs", &"rcd"]
const NOOK_SPECIES := &"rcn"

## Player enter spawn (`SHOP01_player_data`).
const CRANNY_SPAWN_GX := Vector3(160.0, 0.0, 300.0)
const CRANNY_SPAWN_FACING := WorldGrid.Facing.SOUTH

## Shell table tops / `mCoBG` shelf (~21 GX). Floor goods stay at 0.
const CRANNY_SHELF_Y_GX := 21.0
## `aHC_position_data` SCENE_SHOP0 — wall clock GX.
const CLOCK_GX := Vector3(200.0, 40.0, 40.0)
const CLOCK_VISUALS: Array[StringName] = [
	&"obj_clock_shop1", &"obj_clock_shop2", &"obj_clock_shop3", &"obj_clock_shop4"
]

## RSV_SHOP_* cells for Cranny (`l_zakka_goods` fill order → typed slots).
## `y_gx`: freestanding FTR / mannequin / umbrella on the floor; shelf samples on tables.
const CRANNY_SLOTS: Array[Dictionary] = [
	{"kind": &"furniture", "cell": Vector2i(1, 1), "y_gx": 0.0},
	{"kind": &"wall", "cell": Vector2i(3, 1), "y_gx": CRANNY_SHELF_Y_GX},
	{"kind": &"floor", "cell": Vector2i(4, 1), "y_gx": CRANNY_SHELF_Y_GX},
	{"kind": &"tool", "cell": Vector2i(5, 1), "y_gx": CRANNY_SHELF_Y_GX},
	{"kind": &"tool", "cell": Vector2i(6, 1), "y_gx": CRANNY_SHELF_Y_GX},
	{"kind": &"cloth", "cell": Vector2i(1, 3), "y_gx": 0.0},
	{"kind": &"paper", "cell": Vector2i(3, 4), "y_gx": CRANNY_SHELF_Y_GX},
	{"kind": &"plant", "cell": Vector2i(4, 4), "y_gx": CRANNY_SHELF_Y_GX},
	{"kind": &"plant", "cell": Vector2i(5, 4), "y_gx": CRANNY_SHELF_Y_GX},
	{"kind": &"umbrella", "cell": Vector2i(1, 5), "y_gx": 0.0},
]


static func nook_wall_id(level: int) -> StringName:
	return NOOK_WALL_IDS[clampi(level, 0, NOOK_WALL_IDS.size() - 1)]


static func nook_floor_id(level: int) -> StringName:
	return NOOK_FLOOR_IDS[clampi(level, 0, NOOK_FLOOR_IDS.size() - 1)]


static func nook_clock_visual(level: int) -> StringName:
	return CLOCK_VISUALS[clampi(level, 0, CLOCK_VISUALS.size() - 1)]


static func nook_species(level: int) -> StringName:
	return NOOK_SPECIES_IDS[clampi(level, 0, NOOK_SPECIES_IDS.size() - 1)]


static func nook_level_for_room(room_id: StringName) -> int:
	match room_id:
		&"shop1":
			return 1
		&"shop2":
			return 2
		&"shop3_1", &"shop3_2":
			return 3
		_:
			return 0


static func nook_stand_gx(level: int) -> Vector3:
	var ut: Vector2i = NOOK_STAND_UT[clampi(level, 0, NOOK_STAND_UT.size() - 1)]
	return Vector3(float(ut.x) * 40.0 + 20.0, 0.0, float(ut.y) * 40.0 + 20.0)


static func nook_is_shop_room(room_id: StringName) -> bool:
	return room_id == &"shop0" or room_id == &"shop1" or room_id == &"shop2" or room_id == &"shop3_1"


static func gx_to_world(grid: WorldGrid, gx: Vector3) -> Vector3:
	return MuseumDisplay.gx_to_world(grid, gx)


static func stock_cells_for_goods(goods: Array[StringName]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for row: Dictionary in stock_placements_for_goods(goods):
		out.append(row["cell"] as Vector2i)
	return out


static func stock_placements_for_goods(goods: Array[StringName]) -> Array[Dictionary]:
	## Map each listed good onto the first free RSV cell of matching kind.
	var used: Dictionary = {}
	var out: Array[Dictionary] = []
	for item_id: StringName in goods:
		var kind: StringName = _kind_for_item(item_id)
		var slot: Dictionary = _next_slot(kind, used)
		if slot.is_empty():
			slot = _next_slot(&"", used)
		if slot.is_empty():
			break
		var cell: Vector2i = slot["cell"] as Vector2i
		used["%d,%d" % [cell.x, cell.y]] = true
		out.append({"cell": cell, "y_gx": float(slot.get("y_gx", CRANNY_SHELF_Y_GX))})
	return out


static func _next_slot(kind: StringName, used: Dictionary) -> Dictionary:
	for slot: Dictionary in CRANNY_SLOTS:
		var cell: Vector2i = slot["cell"] as Vector2i
		var key := "%d,%d" % [cell.x, cell.y]
		if bool(used.get(key, false)):
			continue
		if kind == &"" or slot["kind"] == kind:
			return slot
	return {}


static func _kind_for_item(item_id: StringName) -> StringName:
	var data: ItemData = ItemCatalog.get_item(item_id)
	if data == null:
		return &""
	if data is FurnitureData:
		return &"furniture"
	if data is ToolData:
		return &"tool"
	match data.category:
		ItemData.Category.CLOTH:
			return &"cloth"
		ItemData.Category.WALL:
			return &"wall"
		ItemData.Category.FLOOR:
			return &"floor"
		_:
			var raw := String(item_id)
			if raw.contains("umbrella") or raw.contains("utiwa"):
				return &"umbrella"
			if data.plant_id != &"" or raw.contains("sapling") or raw.contains("flower"):
				return &"plant"
			return &""


static func display_visual_for_item(item_id: StringName) -> StringName:
	## Shelf props from `ac_shop_goods_data` (`obj_axeT` → `obj_item_axe`, …).
	var data: ItemData = ItemCatalog.get_item(item_id)
	if data == null:
		return &""
	if data is FurnitureData:
		return (data as FurnitureData).visual_id
	if data is ToolData:
		match (data as ToolData).kind:
			ToolData.Kind.AXE:
				return &"obj_item_axe"
			ToolData.Kind.NET:
				return &"obj_item_net"
			ToolData.Kind.FISHING_ROD:
				return &"obj_item_rod"
			ToolData.Kind.SHOVEL:
				return &"obj_item_shovel"
			_:
				var tool_vis: StringName = (data as ToolData).visual_id
				return tool_vis
	match data.category:
		ItemData.Category.CLOTH:
			return &"obj_shop_manekin"
		ItemData.Category.WALL:
			return &"obj_item_wall"
		ItemData.Category.FLOOR:
			return &"obj_item_carpet"
		_:
			var raw := String(item_id)
			if raw.contains("sapling"):
				return &"obj_shop_cnaegi"
			if raw.contains("umbrella"):
				return &"obj_item_umbrella"
			if raw.contains("utiwa"):
				return &"obj_item_utiwa"
			if data.plant_id != &"" or raw.contains("flower"):
				return &"obj_item_seed"
			return &""
