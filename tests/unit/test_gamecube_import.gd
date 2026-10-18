class_name TestGameCubeImport
extends GdUnitTestSuite

const PATH := "user://test_gamecube_import.json"
const SOURCE := "user://test_gamecube_import.gci"

const VERSION := 6
const CHECKSUM := 0x08
const TOWN_ID := 0x1234
const HOUSE_INDEX := 2
## (bx 2, bz 3, ux 5, uz 8) in `home_info`: SIGN unit (21, 39).
const VILLAGER_SIGN := Vector2i(21, 39)
const WEED_UNIT := Vector2i(3, 4)
const APPLE_UNIT := Vector2i(5, 5)
const FOSSIL_UNIT := Vector2i(6, 6)


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true
	Game.reset_session()
	SaveService.delete_save(PATH)
	SaveService.delete_save(SOURCE)


func after_test() -> void:
	SaveService.delete_save(PATH)
	SaveService.delete_save(SOURCE)
	Game.reset_session()
	Clock.reset_to_default()
	Clock.paused = false


func test_gci_and_card_image_hold_the_same_town_file() -> void:
	var file: PackedByteArray = _town_file(_save())
	assert_int(GameCubeCard.town_file(_gci(file)).size()).is_equal(file.size())
	assert_bool(GameCubeCard.town_file(_gci(file)) == file).is_true()
	assert_bool(GameCubeCard.town_file(_card(file)) == file).is_true()
	assert_bool(GameCubeCard.town_file(PackedByteArray([1, 2, 3])).is_empty()).is_true()


func test_damaged_copy_falls_back_to_the_backup() -> void:
	var save: PackedByteArray = _save()
	var file: PackedByteArray = _town_file(save)
	file[GameCubeTown.SAVE_SIZE + 0x100] ^= 0xFF
	assert_int(GameCubeTown.find_save(file)).is_equal(-1)
	assert_bool(GameCubeTown.decode(file).is_empty()).is_true()
	for i: int in save.size():
		file[GameCubeTown.SAVE_SIZE * 2 + i] = save[i]
	assert_int(GameCubeTown.find_save(file)).is_equal(GameCubeTown.SAVE_SIZE * 2)


func test_decode_reads_town_residents_and_villagers() -> void:
	var town: Dictionary = GameCubeTown.decode(_town_file(_save()))
	assert_str(town["town_name"]).is_equal("Maple")
	assert_int(town["town_id"]).is_equal(TOWN_ID)
	assert_int((town["tune"] as PackedByteArray)[0]).is_equal(1)
	assert_int((town["tune"] as PackedByteArray)[1]).is_equal(2)
	var blake: Dictionary = (town["residents"] as Array)[0]
	assert_str(blake["name"]).is_equal("Blake")
	assert_int(blake["gender"]).is_equal(TownImport.FEMALE)
	assert_int(blake["wallet"]).is_equal(5000)
	assert_int(blake["savings"]).is_equal(100000)
	assert_int((blake["pockets"] as Array)[1]["condition"]).is_equal(1)
	assert_int(blake["house"]["plot"]).is_equal(HOUSE_INDEX)
	assert_int(blake["house"]["size"]).is_equal(2)
	assert_int(blake["house"]["next_size"]).is_equal(3)
	assert_bool(blake["house"]["has_basement"]).is_true()
	assert_bool(((town["residents"] as Array)[1] as Dictionary).is_empty()).is_true()
	var villager: Dictionary = (town["villagers"] as Array)[0]
	assert_int(villager["npc_index"]).is_equal(_villager().npc_index)
	assert_that(villager["home"]).is_equal(VILLAGER_SIGN)
	assert_bool(villager["moved_in"]).is_true()
	assert_bool(((town["villagers"] as Array)[1] as Dictionary).is_empty()).is_true()


func test_build_makes_a_save_payload() -> void:
	var built: Dictionary = TownImport.build(GameCubeTown.decode(_town_file(_save())))
	var world: Dictionary = built["payload"]["world"]
	assert_str(world["town_name"]).is_equal("Maple")
	assert_str(str(world["town_fruit"])).is_equal("peach")
	assert_int(world["world_mode"]).is_equal(int(WorldData.Mode.GENERATED))
	assert_int(world["weeds"][String(WeedUse.persist_id(WEED_UNIT))]).is_equal(1)
	assert_str(world["field_items"][String(FieldItems.persist_id(APPLE_UNIT))]["id"]).is_equal("apple")
	var fossil: Dictionary = world["buried"][String(BuriedUse.persist_id(FOSSIL_UNIT))]
	assert_str(fossil[BuriedUse.KEY_KIND]).is_equal(String(BuriedUse.KIND_FOSSIL))
	assert_bool(world["field_items"].has(String(FieldItems.persist_id(FOSSIL_UNIT)))).is_false()
	var villagers: Dictionary = world["residents"]
	assert_str(villagers["slots"][0]["id"]).is_equal(String(_villager().id))
	assert_array(villagers["slots"][0]["home"]).is_equal([VILLAGER_SIGN.x, VILLAGER_SIGN.y])
	var slot: Dictionary = world["roster"]["slots"][0]
	assert_str(slot["player_name"]).is_equal("Blake")
	assert_str(slot["player_gender"]).is_equal("female")
	assert_str(slot[PlayerRoster.KEY_HOUSE]["outdoor_building_id"]).is_equal("player_house_2")
	assert_str(slot[PlayerRoster.KEY_INVENTORY]["slots"][0]["id"]).is_equal("apple")
	assert_str(slot[PlayerRoster.KEY_INVENTORY]["slots"][1]["id"]).is_equal("lions_paw")
	assert_bool((world["roster"]["slots"][1] as Dictionary).is_empty()).is_true()
	assert_int(built["summary"]["residents"]).is_equal(1)
	assert_int(built["summary"]["villagers"]).is_equal(1)


func test_imported_save_loads_into_the_game() -> void:
	var out := FileAccess.open(SOURCE, FileAccess.WRITE)
	out.store_buffer(_gci(_town_file(_save())))
	out.close()
	var report: Dictionary = SaveService.import_gamecube(SOURCE, PATH)
	assert_int(report["error"]).is_equal(OK)
	assert_int(SaveService.load_game(PATH)).is_equal(OK)
	assert_str(Game.town.town_name).is_equal("Maple")
	assert_str(Game.resident.player_name).is_equal("Blake")
	assert_int(Game.inventory.count_of(&"apple")).is_equal(1)
	assert_int(Game.inventory.wallet).is_equal(5000)
	assert_str(String(Game.residents.slots[0]["id"])).is_equal(String(_villager().id))
	assert_bool(Game.town.imported_field.is_empty()).is_false()


func test_unrecognised_file_is_refused() -> void:
	var out := FileAccess.open(SOURCE, FileAccess.WRITE)
	out.store_buffer(PackedByteArray([0, 1, 2, 3]))
	out.close()
	assert_int(SaveService.import_gamecube(SOURCE, PATH)["error"]).is_equal(ERR_FILE_UNRECOGNIZED)
	assert_bool(FileAccess.file_exists(PATH)).is_false()


func test_generator_builds_the_imported_field() -> void:
	if not FieldObjectCatalog.has_catalog() or FieldObjectCatalog.combi(1).is_empty():
		return
	var acres: Array = []
	for i: int in TownFieldGenerator.BLOCK_TOTAL:
		acres.append(1 << 2)
	var field: Array = []
	for i: int in WorldGenerator.FG_X * WorldGenerator.FG_Z:
		var units: Array = []
		units.resize(WorldGenerator.UT * WorldGenerator.UT)
		units.fill(0)
		field.append(units)
	(field[0] as Array)[4 * WorldGenerator.UT + 3] = FieldObjectCatalog.ITEM_TREE
	var data: WorldData = WorldGenerator.generate(TOWN_ID, false, {"acres": acres, "field": field})
	assert_str(data.acre_visuals[TownFieldGenerator.BLOCK_X + 1]).is_equal(String(FieldObjectCatalog.combi(1)["bg"]))
	var trees: int = 0
	var tree_at_unit: bool = false
	for o: ObjectPlacement in data.objects:
		if o != null and o.kind == &"tree":
			trees += 1
			tree_at_unit = tree_at_unit or o.cell == Vector2i(3, 4)
	assert_int(trees).is_equal(1)
	assert_bool(tree_at_unit).is_true()


static func _villager() -> VillagerData:
	for v: VillagerData in VillagerCatalog.all_villagers():
		if v.npc_index >= 0:
			return v
	return null


## A main `Save_t` with one resident, one villager, a weed, an apple, a buried fossil and a
## valid checksum.
static func _save() -> PackedByteArray:
	var s := PackedByteArray()
	s.resize(GameCubeTown.SAVE_SIZE)
	_put32(s, GameCubeTown.CHECK_VERSION, VERSION)
	_put32(s, GameCubeTown.CHECK_CODE, GameCubeTown.SAVE_CODE)
	_text(s, GameCubeTown.LAND_NAME, "Maple")
	_put16(s, GameCubeTown.LAND_ID, TOWN_ID)
	_put16(s, GameCubeTown.FRUIT, CodeItems.FOOD0 + 3)
	s[GameCubeTown.TUNE] = 0x12
	s[GameCubeTown.VILLAGER_MAX] = 6
	var p: int = GameCubeTown.RESIDENTS
	_text(s, p + GameCubeTown.RESIDENT_NAME, "Blake")
	_put16(s, p + GameCubeTown.RESIDENT_LAND_ID, 0x3000 | 0x12)
	s[p + GameCubeTown.RESIDENT_GENDER] = TownImport.FEMALE
	s[p + GameCubeTown.RESIDENT_FACE] = 3
	_put16(s, p + GameCubeTown.RESIDENT_POCKETS, CodeItems.FOOD0)
	_put16(s, p + GameCubeTown.RESIDENT_POCKETS + 2, CodeItems.ETC_FOSSIL + 3)
	_put32(s, p + GameCubeTown.RESIDENT_POCKET_CONDITIONS, 1 << 2)
	_put32(s, p + GameCubeTown.RESIDENT_WALLET, 5000)
	_put32(s, p + GameCubeTown.RESIDENT_SAVINGS, 100000)
	_put16(s, p + GameCubeTown.RESIDENT_CLOTH, CodeItems.CLOTH0 + 9)
	s[GameCubeTown.HOUSE_ARRANGEMENT] = HOUSE_INDEX
	var home: int = GameCubeTown.HOMES + HOUSE_INDEX * GameCubeTown.HOME_SIZE
	s[home + GameCubeTown.HOME_SIZE_BITS] = (2 << 5) | (3 << 2)
	s[home + GameCubeTown.HOME_FLAGS] = 1 << 4
	s[home + GameCubeTown.HOME_ROOF] = 5
	var v: int = GameCubeTown.VILLAGERS
	_put16(s, v + GameCubeTown.VILLAGER_NPC_ID, (GameCubeTown.NPC_NAME_TYPE << 12) | _villager().npc_index)
	s[v + GameCubeTown.VILLAGER_HOME] = 2
	s[v + GameCubeTown.VILLAGER_HOME + 1] = 3
	s[v + GameCubeTown.VILLAGER_HOME + 2] = 5
	s[v + GameCubeTown.VILLAGER_HOME + 3] = 8
	s[v + GameCubeTown.VILLAGER_MOVED_IN] = 1
	_put16(s, _unit(WEED_UNIT), TownImport.WEED_FIRST + 1)
	_put16(s, _unit(APPLE_UNIT), CodeItems.FOOD0)
	_put16(s, _unit(FOSSIL_UNIT), TownImport.FOSSIL)
	_put16(s, GameCubeTown.BURIED + FOSSIL_UNIT.y * 2, 1 << FOSSIL_UNIT.x)
	_put16(s, CHECKSUM, (0x10000 - GameCubeTown.checksum(s, 0)) & 0xFFFF)
	return s


## Acre A-1, unit `u`.
static func _unit(u: Vector2i) -> int:
	return GameCubeTown.FIELD + (u.y * GameCubeTown.UNITS + u.x) * 2


static func _town_file(save: PackedByteArray) -> PackedByteArray:
	var file := PackedByteArray()
	file.resize(GameCubeTown.SAVE_SIZE * 3)
	for i: int in save.size():
		file[GameCubeTown.SAVE_SIZE + i] = save[i]
	return file


static func _entry(blocks: int, first_block: int) -> PackedByteArray:
	var e := PackedByteArray()
	e.resize(GameCubeCard.ENTRY_SIZE)
	_ascii(e, 0, GameCubeCard.GAME_CODE + "01")
	_ascii(e, GameCubeCard.ENTRY_FILE_NAME, GameCubeCard.TOWN_FILE_NAME)
	_put16(e, GameCubeCard.ENTRY_FIRST_BLOCK, first_block)
	_put16(e, GameCubeCard.ENTRY_BLOCK_COUNT, blocks)
	return e


static func _gci(file: PackedByteArray) -> PackedByteArray:
	var out: PackedByteArray = _entry(file.size() / GameCubeCard.BLOCK_SIZE, GameCubeCard.FIRST_DATA_BLOCK)
	out.append_array(file)
	return out


## A card image with the file's blocks stored last-to-first, a stale directory in block 1 and
## the current one (higher counter) in block 2.
static func _card(file: PackedByteArray) -> PackedByteArray:
	var bs: int = GameCubeCard.BLOCK_SIZE
	var n: int = file.size() / bs
	var card := PackedByteArray()
	card.resize((GameCubeCard.FIRST_DATA_BLOCK + n + 2) * bs)
	var first: int = GameCubeCard.FIRST_DATA_BLOCK + n - 1
	var entry: PackedByteArray = _entry(n, first)
	for i: int in entry.size():
		card[2 * bs + i] = entry[i]
	_put16(card, 2 * bs + GameCubeCard.DIRECTORY_COUNTER, 1)
	for k: int in n:
		var block: int = first - k
		for i: int in bs:
			card[block * bs + i] = file[k * bs + i]
		var next: int = GameCubeCard.LAST_BLOCK if k == n - 1 else block - 1
		_put16(card, 3 * bs + GameCubeCard.TABLE_MAP + (block - GameCubeCard.FIRST_DATA_BLOCK) * 2, next)
	return card


static func _put16(buf: PackedByteArray, at: int, value: int) -> void:
	buf[at] = (value >> 8) & 0xFF
	buf[at + 1] = value & 0xFF


static func _put32(buf: PackedByteArray, at: int, value: int) -> void:
	_put16(buf, at, (value >> 16) & 0xFFFF)
	_put16(buf, at + 2, value & 0xFFFF)


## Names are space-padded to eight characters; plain letters share ASCII's codes.
static func _text(buf: PackedByteArray, at: int, value: String) -> void:
	_ascii(buf, at, value.rpad(GameCubeTown.NAME_LEN))


static func _ascii(buf: PackedByteArray, at: int, value: String) -> void:
	var raw: PackedByteArray = value.to_ascii_buffer()
	for i: int in raw.size():
		buf[at + i] = raw[i]
