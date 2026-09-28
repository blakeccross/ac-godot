class_name ShopDisplay
extends RefCounted

## Nook store FG layouts (`FG_TYPE_ROM_SHOP1`…`SHOP4_2`, templates 0x22–0x26) and Tom Nook stand.
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

## Player outdoor enter (`aSHOP_shop_door_data`): GX {160,0,300}, `mSc_DIRECT_NORTH`.
const CRANNY_SPAWN_GX := Vector3(160.0, 0.0, 300.0)
## Each building's own `Door_data_c` (`aSHOP_` / `aCNV_conveni_` / `aSPR_super_` /
## `aDPT_depart_door_data`): the player steps in north of that store's EXIT_DOOR.
const NOOK_SPAWN_GX: Array[Vector3] = [
	CRANNY_SPAWN_GX, Vector3(320.0, 0.0, 300.0), Vector3(320.0, 0.0, 460.0), Vector3(320.0, 0.0, 540.0)
]
## Walkable area and EXIT_DOOR of each upgraded floor, read off its FG template walls
## (`fffe`) like the Cranny's: [inner origin, inner size, door cell]. The inner box runs
## down to the exit row, as the Cranny's does. Nookington's upstairs has no outdoor exit
## in the original (stairs only); its door stays on the south row for now.
const NOOK_ROOM_BOUNDS: Dictionary = {
	&"shop1": [Vector2i(1, 1), Vector2i(10, 8), Vector2i(7, 8)],
	&"shop2": [Vector2i(1, 1), Vector2i(10, 12), Vector2i(7, 12)],
	&"shop3_1": [Vector2i(1, 3), Vector2i(10, 12), Vector2i(7, 14)],
	&"shop3_2": [Vector2i(1, 3), Vector2i(10, 10), Vector2i(7, 12)],
}
const CRANNY_SPAWN_FACING := WorldGrid.Facing.NORTH

## Table tops: `mCoBG` height 6 against the floor's 4 (×10 GX) in every `ROM_SHOP*` bg
## table (`bg_data.c`). Floor goods stay at 0.
const CRANNY_SHELF_Y_GX := 21.0
const SHELF := CRANNY_SHELF_Y_GX
## `aHC_position_data` SCENE_SHOP0 — wall clock GX.
const CLOCK_GX := Vector3(200.0, 40.0, 40.0)
const CLOCK_VISUALS: Array[StringName] = [
	&"obj_clock_shop1", &"obj_clock_shop2", &"obj_clock_shop3", &"obj_clock_shop4"
]

## `RSV_SHOP_*` reserve points of each Nook FG template, in `mSP_SetGoods2ReservedPoint`
## scan order (row-major). Kinds follow `aSD_ItemName2ReservePointName`: `sapling` is
## `RSV_SHOP_HALLOWEEN`, `floor` is carpet. `y_gx` is the unit's table or floor height:
## furniture, mannequins and umbrella stands stand on the floor.
## `FG_TYPE_ROM_SHOP1` (0x22): Nook's Cranny.
const CRANNY_SLOTS: Array[Dictionary] = [
	{"kind": &"furniture", "cell": Vector2i(1, 1), "y_gx": 0.0},
	{"kind": &"wall", "cell": Vector2i(3, 1), "y_gx": SHELF},
	{"kind": &"floor", "cell": Vector2i(4, 1), "y_gx": SHELF},
	{"kind": &"tool", "cell": Vector2i(5, 1), "y_gx": SHELF},
	{"kind": &"tool", "cell": Vector2i(6, 1), "y_gx": SHELF},
	{"kind": &"cloth", "cell": Vector2i(1, 3), "y_gx": 0.0},
	{"kind": &"paper", "cell": Vector2i(3, 4), "y_gx": SHELF},
	{"kind": &"plant", "cell": Vector2i(4, 4), "y_gx": SHELF},
	{"kind": &"plant", "cell": Vector2i(5, 4), "y_gx": SHELF},
	{"kind": &"sapling", "cell": Vector2i(6, 4), "y_gx": SHELF},
	{"kind": &"umbrella", "cell": Vector2i(1, 5), "y_gx": 0.0},
]
## `FG_TYPE_ROM_SHOP2` (0x23): Nook 'n' Go.
const CONVENI_SLOTS: Array[Dictionary] = [
	{"kind": &"sapling", "cell": Vector2i(2, 1), "y_gx": SHELF},
	{"kind": &"plant", "cell": Vector2i(3, 1), "y_gx": SHELF},
	{"kind": &"plant", "cell": Vector2i(4, 1), "y_gx": SHELF},
	{"kind": &"plant", "cell": Vector2i(5, 1), "y_gx": SHELF},
	{"kind": &"cloth", "cell": Vector2i(6, 1), "y_gx": 0.0},
	{"kind": &"cloth", "cell": Vector2i(7, 1), "y_gx": 0.0},
	{"kind": &"furniture", "cell": Vector2i(9, 1), "y_gx": 0.0},
	{"kind": &"floor", "cell": Vector2i(2, 3), "y_gx": SHELF},
	{"kind": &"wall", "cell": Vector2i(3, 3), "y_gx": SHELF},
	{"kind": &"paper", "cell": Vector2i(4, 3), "y_gx": SHELF},
	{"kind": &"paper", "cell": Vector2i(5, 3), "y_gx": SHELF},
	{"kind": &"furniture", "cell": Vector2i(9, 3), "y_gx": 0.0},
	{"kind": &"tool", "cell": Vector2i(2, 5), "y_gx": SHELF},
	{"kind": &"tool", "cell": Vector2i(3, 5), "y_gx": SHELF},
	{"kind": &"sign", "cell": Vector2i(4, 5), "y_gx": SHELF},
	{"kind": &"umbrella", "cell": Vector2i(5, 5), "y_gx": 0.0},
]
## `FG_TYPE_ROM_SHOP3` (0x24): Nookway.
const SUPER_SLOTS: Array[Dictionary] = [
	{"kind": &"rare", "cell": Vector2i(1, 1), "y_gx": 0.0},
	{"kind": &"furniture", "cell": Vector2i(5, 1), "y_gx": 0.0},
	{"kind": &"furniture", "cell": Vector2i(7, 1), "y_gx": 0.0},
	{"kind": &"furniture", "cell": Vector2i(9, 1), "y_gx": 0.0},
	{"kind": &"sapling", "cell": Vector2i(1, 4), "y_gx": SHELF},
	{"kind": &"wall", "cell": Vector2i(3, 4), "y_gx": SHELF},
	{"kind": &"wall", "cell": Vector2i(5, 4), "y_gx": SHELF},
	{"kind": &"cloth", "cell": Vector2i(7, 4), "y_gx": 0.0},
	{"kind": &"cloth", "cell": Vector2i(8, 4), "y_gx": 0.0},
	{"kind": &"cloth", "cell": Vector2i(9, 4), "y_gx": 0.0},
	{"kind": &"sapling", "cell": Vector2i(1, 5), "y_gx": SHELF},
	{"kind": &"floor", "cell": Vector2i(3, 5), "y_gx": SHELF},
	{"kind": &"floor", "cell": Vector2i(5, 5), "y_gx": SHELF},
	{"kind": &"plant", "cell": Vector2i(1, 6), "y_gx": SHELF},
	{"kind": &"tool", "cell": Vector2i(3, 6), "y_gx": SHELF},
	{"kind": &"paper", "cell": Vector2i(5, 6), "y_gx": SHELF},
	{"kind": &"plant", "cell": Vector2i(1, 7), "y_gx": SHELF},
	{"kind": &"tool", "cell": Vector2i(3, 7), "y_gx": SHELF},
	{"kind": &"paper", "cell": Vector2i(5, 7), "y_gx": SHELF},
	{"kind": &"plant", "cell": Vector2i(1, 8), "y_gx": SHELF},
	{"kind": &"sign", "cell": Vector2i(3, 8), "y_gx": SHELF},
	{"kind": &"paper", "cell": Vector2i(5, 8), "y_gx": SHELF},
	{"kind": &"plant", "cell": Vector2i(1, 9), "y_gx": SHELF},
	{"kind": &"paint", "cell": Vector2i(3, 9), "y_gx": SHELF},
	{"kind": &"umbrella", "cell": Vector2i(5, 9), "y_gx": 0.0},
]
## `FG_TYPE_ROM_SHOP4_1` (0x25): Nookington's ground floor.
const DEPART_1F_SLOTS: Array[Dictionary] = [
	{"kind": &"tool", "cell": Vector2i(2, 3), "y_gx": SHELF},
	{"kind": &"tool", "cell": Vector2i(3, 3), "y_gx": SHELF},
	{"kind": &"tool", "cell": Vector2i(4, 3), "y_gx": SHELF},
	{"kind": &"sign", "cell": Vector2i(5, 3), "y_gx": SHELF},
	{"kind": &"paint", "cell": Vector2i(6, 3), "y_gx": SHELF},
	{"kind": &"sapling", "cell": Vector2i(1, 4), "y_gx": SHELF},
	{"kind": &"sapling", "cell": Vector2i(1, 5), "y_gx": SHELF},
	{"kind": &"sapling", "cell": Vector2i(1, 6), "y_gx": SHELF},
	{"kind": &"paper", "cell": Vector2i(5, 6), "y_gx": SHELF},
	{"kind": &"plant", "cell": Vector2i(1, 7), "y_gx": SHELF},
	{"kind": &"paper", "cell": Vector2i(5, 7), "y_gx": SHELF},
	{"kind": &"plant", "cell": Vector2i(1, 8), "y_gx": SHELF},
	{"kind": &"paper", "cell": Vector2i(5, 8), "y_gx": SHELF},
	{"kind": &"plant", "cell": Vector2i(1, 9), "y_gx": SHELF},
	{"kind": &"paper", "cell": Vector2i(5, 9), "y_gx": SHELF},
	{"kind": &"plant", "cell": Vector2i(1, 10), "y_gx": SHELF},
	{"kind": &"paper", "cell": Vector2i(5, 10), "y_gx": SHELF},
	{"kind": &"plant", "cell": Vector2i(1, 11), "y_gx": SHELF},
	{"kind": &"umbrella", "cell": Vector2i(5, 11), "y_gx": 0.0},
]
## `FG_TYPE_ROM_SHOP4_2` (0x26): Nookington's upstairs. `SCENE_DEPART_2` lays out the same
## goods list, so each floor shows only the kinds it has reserve points for.
const DEPART_2F_SLOTS: Array[Dictionary] = [
	{"kind": &"floor", "cell": Vector2i(1, 3), "y_gx": SHELF},
	{"kind": &"floor", "cell": Vector2i(1, 4), "y_gx": SHELF},
	{"kind": &"furniture", "cell": Vector2i(3, 4), "y_gx": 0.0},
	{"kind": &"furniture", "cell": Vector2i(5, 4), "y_gx": 0.0},
	{"kind": &"floor", "cell": Vector2i(1, 5), "y_gx": SHELF},
	{"kind": &"furniture", "cell": Vector2i(8, 5), "y_gx": 0.0},
	{"kind": &"wall", "cell": Vector2i(1, 6), "y_gx": SHELF},
	{"kind": &"wall", "cell": Vector2i(1, 7), "y_gx": SHELF},
	{"kind": &"rare", "cell": Vector2i(5, 7), "y_gx": 0.0},
	{"kind": &"furniture", "cell": Vector2i(8, 7), "y_gx": 0.0},
	{"kind": &"wall", "cell": Vector2i(1, 8), "y_gx": SHELF},
	{"kind": &"furniture", "cell": Vector2i(8, 9), "y_gx": 0.0},
	{"kind": &"cloth", "cell": Vector2i(2, 10), "y_gx": 0.0},
	{"kind": &"cloth", "cell": Vector2i(3, 10), "y_gx": 0.0},
	{"kind": &"cloth", "cell": Vector2i(4, 10), "y_gx": 0.0},
	{"kind": &"cloth", "cell": Vector2i(5, 10), "y_gx": 0.0},
	{"kind": &"cloth", "cell": Vector2i(6, 10), "y_gx": 0.0},
]
## Room → FG template id (`mSP_GetNowShopFgNum`), to check the tables against the disc.
const STOCK_FG_TYPES: Dictionary = {
	&"shop0": 0x22, &"shop1": 0x23, &"shop2": 0x24, &"shop3_1": 0x25, &"shop3_2": 0x26,
}
## `aSD_MakeHukubukuroFg`: grab bags fill these reserve kinds, in this order.
const GRAB_BAG_KINDS: Array[StringName] = [&"tool", &"sign", &"paint", &"paper", &"sapling", &"plant"]


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


static func nook_spawn_gx(room_id: StringName) -> Vector3:
	return NOOK_SPAWN_GX[nook_level_for_room(room_id)]


## Applies `NOOK_ROOM_BOUNDS` to an upgraded floor's room template.
static func apply_room_bounds(room: Room) -> void:
	if room == null or not NOOK_ROOM_BOUNDS.has(room.id):
		return
	var row: Array = NOOK_ROOM_BOUNDS[room.id]
	room.inner_origin = row[0] as Vector2i
	room.inner_size = row[1] as Vector2i
	room.door_cell = row[2] as Vector2i
	room.spawn_cell = room.door_cell + Vector2i(0, -1)


static func nook_stand_gx(level: int) -> Vector3:
	var ut: Vector2i = NOOK_STAND_UT[clampi(level, 0, NOOK_STAND_UT.size() - 1)]
	return Vector3(float(ut.x) * 40.0 + 20.0, 0.0, float(ut.y) * 40.0 + 20.0)


static func nook_is_shop_room(room_id: StringName) -> bool:
	return room_id == &"shop0" or room_id == &"shop1" or room_id == &"shop2" or room_id == &"shop3_1"


static func gx_to_world(grid: WorldGrid, gx: Vector3) -> Vector3:
	return MuseumDisplay.gx_to_world(grid, gx)


## Reserve points of a Nook room's FG template (empty for any other room).
static func stock_slots(room_id: StringName) -> Array[Dictionary]:
	match room_id:
		&"shop0":
			return CRANNY_SLOTS
		&"shop1":
			return CONVENI_SLOTS
		&"shop2":
			return SUPER_SLOTS
		&"shop3_1":
			return DEPART_1F_SLOTS
		&"shop3_2":
			return DEPART_2F_SLOTS
	return []


static func stock_cells_for_goods(
	goods: Array[StringName], room_id: StringName = &"shop0"
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for row: Dictionary in stock_placements_for_goods(goods, room_id):
		out.append(row["cell"] as Vector2i)
	return out


## `aSD_MakeGoodsFg`: each good, in list order, takes the first free reserve point of its
## kind; one with no free point of its kind is not shown (`mSP_SetGoods2ReservedPoint`
## fails). Pass the whole day's list, sold slots included, so every good keeps its point
## for the day. Rows are `{index, cell, y_gx}`, `index` into `goods`.
static func stock_placements_for_goods(
	goods: Array[StringName], room_id: StringName = &"shop0", rare: StringName = &"",
	halloween: bool = false
) -> Array[Dictionary]:
	var slots: Array[Dictionary] = stock_slots(room_id)
	var used: Dictionary = {}
	var out: Array[Dictionary] = []
	for i: int in goods.size():
		var item_id: StringName = goods[i]
		var kinds: Array[StringName] = [_kind_for_item(item_id, rare, halloween)]
		if item_id == ShopGoods.GRAB_BAG:
			kinds = GRAB_BAG_KINDS
		var slot: Dictionary = {}
		for kind: StringName in kinds:
			slot = _next_slot(slots, kind, used)
			if not slot.is_empty():
				break
		if slot.is_empty():
			continue
		var cell: Vector2i = slot["cell"] as Vector2i
		used[cell] = true
		out.append({"index": i, "cell": cell, "y_gx": float(slot["y_gx"])})
	return out


static func _next_slot(slots: Array[Dictionary], kind: StringName, used: Dictionary) -> Dictionary:
	if kind == &"":
		return {}
	for slot: Dictionary in slots:
		if slot["kind"] == kind and not used.has(slot["cell"]):
			return slot
	return {}


## `aSD_ItemName2ReservePointName`.
static func _kind_for_item(item_id: StringName, rare: StringName = &"", halloween: bool = false) -> StringName:
	if item_id == &"":
		return &""
	if item_id == rare:
		return &"rare"
	if item_id == ShopGoods.SIGNBOARD:
		return &"sign"
	if item_id == ShopGoods.PAPER:
		return &"paper"
	if ShopGoods.PAINTS.has(item_id):
		return &"paint"
	if item_id == ShopGoods.SAPLING or item_id == ShopGoods.CEDAR_SAPLING:
		return &"sapling"
	if ShopGoods.FLOWER_BAGS.has(item_id):
		## Halloween: the flower bags stand in for saplings, candy takes the plant points.
		return &"sapling" if halloween else &"plant"
	if item_id == ShopGoods.CANDY:
		return &"plant"
	var data: ItemData = ItemCatalog.get_item(item_id)
	if data == null:
		return &""
	if data is FurnitureData:
		return &"furniture"
	if data is ToolData and (data as ToolData).kind == ToolData.Kind.UMBRELLA:
		return &"umbrella"
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
			if raw.contains("sapling"):
				return &"sapling"
			if data.plant_id != &"" or raw.contains("flower"):
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
			ToolData.Kind.UMBRELLA:
				## `ac_shop_umbrella`: the stand shows that umbrella open (`obj_shop_umbNN`).
				return StringName("obj_shop_umb%02d" % ((data as ToolData).umbrella_index + 1))
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
