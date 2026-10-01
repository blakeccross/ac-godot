class_name MoneyRock
extends RefCounted

## The money rock (`mAGrw_SetMoneyStone`, `bIT_actor_ten_coin_entryR`). At each renewal, if
## the town has no money rock, one ordinary rock becomes one: a random field acre that has
## rocks, then a random rock in it. It looks like any other rock. The first shovel hit starts a
## window of `386 + money power × 0.6` ticks (`left_frames`, counted down once per 60 Hz
## play-loop tick: about 6.4 s); every hit inside it knocks a
## bag of Bells onto a free unit next to the rock, worth more as the hits go on (100 for hits
## 1–3, 1,000 for 4–6, then 10,000). With no free unit around, the hit drops nothing. When the
## window runs out the rock is ordinary again until the next renewal picks a new one.

const WINDOW_FRAMES := 386.0
const POWER_FRAMES := 0.6
const POWER_MAX := 100
## `mPr_MONEY_POWER_MIN`.
const POWER_MIN := -80
## `BI_chk_pos`, searched from the end: the rock's own unit, then N, E, S, W, then corners.
const AROUND: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(1, 1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 0),
]
const SE_HIT := &"426"

## Hits so far in the running window, and when it closes (`Time.get_ticks_msec`).
static var _active_id: StringName = &""
static var _hits: int = 0
static var _ends_msec: int = 0


static func is_money_rock(id: StringName) -> bool:
	return id != &"" and String(id) == Game.money_rock


## `mPr_GetMoneyPower`: no feng shui yet, so only the day's fortune moves it.
static func money_power() -> int:
	var power: int = 0
	match Game.destiny():
		Game.Destiny.MONEY_LUCK:
			power += 100
		Game.Destiny.BAD_LUCK:
			power -= 50
	return maxi(power, POWER_MIN)


## `left_frames` in ticks. The money-luck line subtracts the bonus straight back off (`@BUG`).
static func window_frames(power: int, money_luck: bool) -> float:
	var swing: int = power - (100 if money_luck else 0)
	return WINDOW_FRAMES + float(mini(swing, POWER_MAX)) * POWER_FRAMES


## The bag for hit `hit` (0-based) of a window.
static func payout(hit: int, money_luck: bool) -> StringName:
	if hit <= 2:
		return &"money_1000" if money_luck else &"money_100"
	if hit <= 5:
		return &"money_10000" if money_luck else &"money_1000"
	return &"money_30000" if money_luck else &"money_10000"


## `mAGrw_SetMoneyStone_com`: pick a random acre with rocks, then a random rock there.
## `rocks` maps rock id → its field block.
static func choose(rocks: Dictionary, rng: RandomNumberGenerator) -> StringName:
	var by_block: Dictionary = {}
	var ids: Array = rocks.keys()
	ids.sort()
	for id: Variant in ids:
		var block: Vector2i = rocks[id]
		if not by_block.has(block):
			by_block[block] = []
		(by_block[block] as Array).append(id)
	if by_block.is_empty():
		return &""
	var blocks: Array = by_block.keys()
	blocks.sort()
	var picks: Array = by_block[blocks[rng.randi_range(0, blocks.size() - 1)]]
	return StringName(str(picks[rng.randi_range(0, picks.size() - 1)]))


## Renewal: keep a money rock that is still there, otherwise pick a new one, at most once a
## day (`today`: `Clock.day_number`).
static func renew(world: Node, rng: RandomNumberGenerator, today: int) -> void:
	var rocks: Dictionary = field_rocks(world)
	if Game.money_rock != "" and rocks.has(StringName(Game.money_rock)):
		return
	if Game.money_rock_day == today:
		return
	Game.money_rock = String(choose(rocks, rng))
	Game.money_rock_day = today


## Rocks on the field acres (blocks 1–5 × 1–6), by id.
static func field_rocks(world: Node) -> Dictionary:
	var out: Dictionary = {}
	if world == null or world.get_tree() == null:
		return out
	var grid: WorldGrid = world.get("grid") as WorldGrid
	if grid == null:
		return out
	for node: Node in world.get_tree().get_nodes_in_group("interactable"):
		if not node is Node3D or not node.has_method("is_rock") or node.is_queued_for_deletion():
			continue
		var id: StringName = node.get("occupant_id") as StringName
		if id == &"":
			continue
		var block: Vector2i = grid.world_to_cell((node as Node3D).global_position) / 16
		if block.x >= 1 and block.x <= TownAssessment.FG_BLOCK_X and block.y >= 1 and block.y <= TownAssessment.FG_BLOCK_Z:
			out[id] = block
	return out


## One shovel hit. Returns the bag to drop (null: none), and ends the rock when its window
## has closed. `now_msec` is injectable for tests.
static func hit(id: StringName, now_msec: int = -1) -> ItemData:
	if not is_money_rock(id):
		return null
	var now: int = now_msec if now_msec >= 0 else Time.get_ticks_msec()
	if _active_id == id and now >= _ends_msec:
		## The window closed: back to an ordinary rock (`ten_coin_move`).
		finish()
		return null
	var luck: bool = Game.destiny() == Game.Destiny.MONEY_LUCK
	if _active_id != id:
		_active_id = id
		_hits = 0
		var frames: float = window_frames(money_power(), luck)
		_ends_msec = now + int(DecompTime.ticks_to_sec(frames) * 1000.0)
	else:
		_hits += 1
	return ItemCatalog.get_item(payout(_hits, luck))


static func active_hits() -> int:
	return _hits if _active_id != &"" else -1


static func window_open(now_msec: int = -1) -> bool:
	var now: int = now_msec if now_msec >= 0 else Time.get_ticks_msec()
	return _active_id != &"" and now < _ends_msec


static func finish() -> void:
	if _active_id != &"" and String(_active_id) == Game.money_rock:
		Game.money_rock = ""
	_active_id = &""
	_hits = 0
	_ends_msec = 0


static func reset() -> void:
	_active_id = &""
	_hits = 0
	_ends_msec = 0


## `mFI_search_unit_around_high`: the first free unit around `cell`, or (-1, -1).
static func drop_cell(grid: WorldGrid, cell: Vector2i) -> Vector2i:
	if grid == null:
		return Vector2i(-1, -1)
	for i: int in range(AROUND.size() - 1, -1, -1):
		var c: Vector2i = cell + AROUND[i]
		if grid.can_place(c, Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.ITEM):
			return c
	return Vector2i(-1, -1)
