class_name FengShui
extends RefCounted

## Feng shui (`m_huusui_room_ovl.c`): the player's rooms are scored whenever the field is
## left or a game starts (`mHsRm_GetHuusuiRoom`). Each piece of furniture has a colour
## (`mMkRm_ftr_info`, from the disc via `FtrCatalog`): yellow pays money power on the west
## side, red goods power on the east, orange both on the north, green both on the south;
## lucky items pay both anywhere. A piece counts for a side only when every unit it covers
## is in that side's band (one unit from the wall in a small room for 1×1 pieces, else two).
## A piece with a face (dolls, figures) pressed against a wall and turned to face it costs
## 10 money and 5 goods power. Goods power is capped at 40 and halved, rounding up. Money
## power feeds the money rock and money trees, goods power Nook's rare odds. Nothing counts
## while doing Nook's chores (`mEv_CheckFirstJob`).

enum Colour { NONE, YELLOW, RED, ORANGE, GREEN, LUCKY }
## `mHsRm_DIRECTION_*`, the same order as `WorldGrid.Facing`.
enum Dir { SOUTH, EAST, NORTH, WEST }

const MONEY_LUCKY := 4
const GOODS_LUCKY := 8
const MONEY_BAD := 10
const GOODS_BAD := 5
const GOODS_MAX := 40
## `mHsRm_unit_max` for the small room: its 1×1 pieces count one unit from the wall.
const UNIT_MAX_SMALL := 6
const ALL := 0b1111
## `money_power_tbl` / `goods_power_tbl`: [walls bitmask, points] per colour.
const MONEY: Array = [[0, 0], [1 << Dir.WEST, 4], [0, 0], [1 << Dir.NORTH, 2], [1 << Dir.SOUTH, 2], [ALL, 4]]
const GOODS: Array = [[0, 0], [0, 0], [1 << Dir.EAST, 8], [1 << Dir.NORTH, 4], [1 << Dir.SOUTH, 4], [ALL, 8]]

static var _by_visual: Dictionary = {}


## `mHsRm_EvaluateHuusuiPoint_Single`: one piece covering `cells` (room units, walls at 0 and
## `ut_max - 1`), turned to `rot`. Returns (money, goods).
static func score_piece(cells: Array[Vector2i], colour: int, face: bool, rot: int, ut_max: int) -> Vector2i:
	var n: int = cells.size()
	if n == 0:
		return Vector2i.ZERO
	var start: int = 1 if ut_max == UNIT_MAX_SMALL and n == 1 else 2
	var side: Array[int] = [0, 0, 0, 0]
	var touch: Array[int] = [0, 0, 0, 0]
	for c: Vector2i in cells:
		if c.y <= start:
			side[Dir.NORTH] += 1
			if c.y <= 1:
				touch[Dir.NORTH] += 1
		elif c.y >= ut_max - start - 1:
			side[Dir.SOUTH] += 1
			if c.y >= ut_max - 2:
				touch[Dir.SOUTH] += 1
		if c.x <= start:
			side[Dir.WEST] += 1
			if c.x <= 1:
				touch[Dir.WEST] += 1
		elif c.x >= ut_max - start - 1:
			side[Dir.EAST] += 1
			if c.x >= ut_max - 2:
				touch[Dir.EAST] += 1
	var side_bits: int = 0
	var wall_bits: int = 0
	for i: int in 4:
		if side[i] == n:
			side_bits |= 1 << i
		if (n >= 2 and touch[i] >= 2) or (n == 1 and touch[i] >= 1):
			wall_bits |= 1 << i
	var money: int = 0
	var goods: int = 0
	if colour == Colour.LUCKY:
		money += MONEY_LUCKY
		goods += GOODS_LUCKY
	if side_bits == 0:
		return Vector2i(money, goods)
	if colour != Colour.LUCKY and colour > 0 and colour < MONEY.size():
		for i: int in 4:
			if side_bits & (1 << i):
				if int(MONEY[colour][0]) & (1 << i):
					money += int(MONEY[colour][1])
				if int(GOODS[colour][0]) & (1 << i):
					goods += int(GOODS[colour][1])
	if face:
		for i: int in 4:
			if (wall_bits & (1 << i)) and rot == i:
				money -= MONEY_BAD
				goods -= GOODS_BAD
	return Vector2i(money, goods)


## The cap and the halving, rounding up (`mHsRm_HuusuiRoomOvl`).
static func finish_goods(goods: int) -> int:
	var g: int = mini(goods, GOODS_MAX)
	return ceili(float(g) * 0.5) if g > 0 else int(float(g) * 0.5)


## (colour, has face) for a piece, by its disc number or its model.
static func info(data: FurnitureData) -> Vector2i:
	if data == null:
		return Vector2i.ZERO
	var idx: int = FtrCatalog.index_of(data.id)
	if idx < 0:
		if _by_visual.is_empty():
			for i: int in FtrCatalog.count():
				var r: Dictionary = FtrCatalog.row(i)
				var v := StringName(str(r.get("visual", "")))
				if v != &"" and not _by_visual.has(v):
					_by_visual[v] = i
		idx = int(_by_visual.get(data.visual_id, -1))
	if idx < 0:
		return Vector2i.ZERO
	var row: Dictionary = FtrCatalog.row(idx)
	return Vector2i(int(row.get("huusui", 0)), 1 if bool(row.get("face", false)) else 0)


## Every piece in one room (both layers). Returns (money, goods) before the goods finish.
static func score_room(room: Room, ut_max: int) -> Vector2i:
	var total := Vector2i.ZERO
	if room == null:
		return total
	var grid := WorldGrid.new()
	for entry: FurniturePlacement in room.placements:
		if entry == null:
			continue
		var data := ItemCatalog.get_item(entry.furniture_id) as FurnitureData
		if data == null:
			continue
		var size: Vector2i = entry.footprint if entry.footprint != Vector2i.ZERO else data.resolved_footprint()
		var cells: Array[Vector2i] = grid.footprint_cells(entry.cell, size, entry.facing)
		var fi: Vector2i = info(data)
		total += score_piece(cells, fi.x, fi.y != 0, int(entry.facing), ut_max)
	return total


## `mHsRm_GetHuusuiRoom`: money and goods power for the player's house now.
static func evaluate() -> Vector2i:
	if Game == null or Game.interiors == null:
		return Vector2i.ZERO
	if Game.first_job != null and Game.first_job.is_active():
		return Vector2i.ZERO
	var house: House = Game.interiors.player_house()
	var tier: int = PlayerHouse.tier_of(house)
	var total: Vector2i = score_room(
		Game.interiors.room(PlayerHouse.MAIN), PlayerHouse.MAIN_INNER[clampi(tier, 0, 3)].x + 2
	)
	if tier >= int(House.SizeTier.UPPER):
		total += score_room(Game.interiors.room(PlayerHouse.UPPER), PlayerHouse.UPPER_INNER.x + 2)
	if house != null and house.has_basement:
		total += score_room(Game.interiors.room(PlayerHouse.BASEMENT), PlayerHouse.BASEMENT_INNER.x + 2)
	return Vector2i(total.x, finish_goods(total.y))
