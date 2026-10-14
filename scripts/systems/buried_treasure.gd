class_name BuriedTreasure
extends RefCounted

## A villager buries something and says where on the community board
## (`mNtc_check_treasure`, `mFI_SetTreasure`). Looked at when the board is checked and no
## seasonal notice went up, once a day from 06:00, three days or more after the last one,
## if a resident remembers the player: a 40% chance. A third of the time it's a pitfall
## seed, otherwise lottery or event furniture. It goes into a random free diggable unit of
## a random acre (not the station's, the houses', the wishing well's or the pond's) under a
## crack mark, and the villager's post (0x1F0 + looks × 3 + rand(3)) names the item and the
## acre ("Acre C-4").

const MIN_DAYS := 3
const CHANCE := 0.4
const POST_FIRST := 0x1F0
## `choume_str`: the acre rows.
const ROWS := "QABCDEF"
const PITFALL := &"pitfall"


## `mNtc_check_treasure`'s time gates (ordinals; 0 = never).
static func due(today: int, hour: int, buried: int, checked: int) -> bool:
	if hour < NoticeBoard.RENEW_HOUR or checked == today:
		return false
	return buried <= 0 or absi(today - buried) >= MIN_DAYS


## A third pitfall seed, a third lottery furniture, a third event furniture.
static func pick_item(rng: RandomNumberGenerator) -> StringName:
	var r: float = rng.randf()
	if r < 1.0 / 3.0:
		return PITFALL
	return FtrCatalog.pick("lottery" if r < 2.0 / 3.0 else "event", rng)


## `mFI_SetTreasure`: a random acre with room, then a random unit in it. Returns the cell.
static func bury(world: Node, item: StringName, rng: RandomNumberGenerator) -> Vector2i:
	var grid: WorldGrid = world.get("grid") as WorldGrid if world != null else null
	if grid == null or item == &"":
		return Vector2i(-1, -1)
	var layout: WorldData = world.get("layout") as WorldData
	var by_block: Dictionary = {}
	for z: int in grid.rows:
		for x: int in grid.columns:
			var cell := Vector2i(x, z)
			var block: Vector2i = VillagerWalk.block_from_cell(cell)
			if not VillagerWalk.is_fg_block(block) or not BuriedUse.can_bury(grid, cell, layout):
				continue
			if not by_block.has(block):
				by_block[block] = []
			(by_block[block] as Array).append(cell)
	if by_block.is_empty():
		return Vector2i(-1, -1)
	var blocks: Array = by_block.keys()
	blocks.sort()
	var cells: Array = by_block[blocks[rng.randi_range(0, blocks.size() - 1)]]
	var pick: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
	return pick if BuriedUse.bury_item(world, pick, item) else Vector2i(-1, -1)


## `mNtc_set_treasure_string` + the post.
static func post_text(looks: int, variant: int, villager: String, item: StringName, block: Vector2i, town: String) -> String:
	var data: ItemData = ItemCatalog.get_item(item)
	var item_name: String = data.display_name if data != null else String(item)
	var text: String = MailBank.text("mail", POST_FIRST + clampi(looks, 0, 5) * 3 + clampi(variant, 0, 2))
	text = text.replace("{cutart}{free2}", item_name)
	var slots: Dictionary = {
		1: villager, 2: PoliceTalk.with_article(item_name), 3: ROWS.substr(clampi(block.y, 0, 6), 1),
		4: str(block.x), 5: town,
	}
	for key: Variant in slots:
		text = text.replace("{free%d}" % int(key), str(slots[key]))
	return text


## Residents who remember the player.
static func senders(residents: TownResidents, book: RelationshipBook) -> Array[VillagerData]:
	var out: Array[VillagerData] = []
	for id: StringName in residents.resident_ids():
		var v: VillagerData = VillagerCatalog.get_villager(id)
		if v != null and book.has_id(id) and book.get_or_create(id).has_memory:
			out.append(v)
	return out


## The whole check against `Game` (`force` skips the gates and the roll). Returns the
## buried cell, or (-1, -1).
static func check(world: Node, rng: RandomNumberGenerator, force: bool = false) -> Vector2i:
	var today: int = EventDates.ordinal(Clock.year, Clock.month, Clock.day)
	if not force and not due(today, Clock.hour, Game.treasure_buried_day, Game.treasure_checked_day):
		return Vector2i(-1, -1)
	Game.treasure_checked_day = today
	var who: Array[VillagerData] = senders(Game.residents, Game.relationships)
	if force and who.is_empty():
		for id: StringName in Game.residents.resident_ids():
			var v: VillagerData = VillagerCatalog.get_villager(id)
			if v != null:
				who.append(v)
	if who.is_empty() or (not force and rng.randf() >= CHANCE):
		return Vector2i(-1, -1)
	var item: StringName = pick_item(rng)
	var cell: Vector2i = bury(world, item, rng)
	if cell.x < 0:
		return cell
	var sender: VillagerData = who[rng.randi_range(0, who.size() - 1)]
	var looks: int = int(sender.personality.looks) if sender.personality != null else 0
	Game.notice_board.write(NoticeBoard._post(
		post_text(looks, rng.randi_range(0, 2), sender.display_name, item, VillagerWalk.block_from_cell(cell),
			Game.town_name),
		Clock.year, Clock.month, Clock.day, Clock.hour, Clock.minute))
	Game.treasure_buried_day = today
	return cell
