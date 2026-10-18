class_name GameCubeTown
extends RefCounted

## Reads a GameCube town save (`Save_t`, `m_common_data.h`) out of the Memory Card town file
## (`GameCubeCard.town_file`) into plain values: names, the acre map and what stands on it,
## the villagers and their homes, and each resident's pockets, money and house. Only what
## `TownImport` carries over is read. USA release (`GAFE`), save versions 5 and 6.
##
## `decode` returns `{}` when no copy passes the save check, else:
##   `town_name`, `town_id`, `saved_at` {year, month, day, hour, minute, second},
##   `fruit` (item number), `tune` (16 notes), `grass_pattern`, `statues`, `villager_max`,
##   `acres` (70 raw `combi_table` words, 7 × 10, row-major),
##   `field` (30 acres, 5 × 6 row-major, each 256 item numbers row-major),
##   `buried` (30 acres, each 16 rows of one bit per unit),
##   `residents` (4: `{}` or {name, gender, face, wallet, savings, loan, cloth, pockets, house}),
##   `villagers` (15: `{}` or {npc_index, home (SIGN unit, or (-1, -1)), moved_in, cloth}).

## The town file holds three 0x26000-byte `Save` areas (`l_mcd_file_table`): the first opens
## with the card comment, banner and icon and keeps letters, designs and the diary; the second
## is the save (`mCD_FILE_SAVE_MAIN`), the third its backup (`mCD_FILE_SAVE_MAIN_BAK`).
const SAVE_SIZE := 0x26000
const SAVE_OFFSETS: Array[int] = [SAVE_SIZE, SAVE_SIZE * 2, 0]
## `mFRm_SAVE_ID` ('GAFE') and the versions `mCD_LoadLand` accepts.
const SAVE_CODE := 0x47414645
const SAVE_VERSIONS: Array[int] = [5, 6]
const RESIDENT_NUM := 4
const VILLAGER_NUM := 15
const FIELD_X := 5
const FIELD_Z := 6
const UNITS := 16
const BLOCK_NUM := 70
const NO_HOME := Vector2i(-1, -1)

## `mFRm_chk_t save_check`.
const CHECK_VERSION := 0x00
const CHECK_CODE := 0x04
const CHECK_TIME := 0x0A
## `Save_t`.
const VILLAGER_MAX := 0x18
const RESIDENTS := 0x20
const RESIDENT_SIZE := 0x2440
const LAND_NAME := 0x9120
const LAND_ID := 0x912A
const HOMES := 0x9CE8
const HOME_SIZE := 0x26B0
const FIELD := 0x137A8
const ACRES := 0x173A8
const VILLAGERS := 0x17438
const VILLAGER_SIZE := 0x988
const FRUIT := 0x20688
const HOUSE_ARRANGEMENT := 0x2068A
const STATUES := 0x2068B
const TUNE := 0x20F08
const BURIED := 0x20F1C
const GRASS_PATTERN := 0x24184
## `Private_c`.
const RESIDENT_NAME := 0x0000
const RESIDENT_LAND_ID := 0x0012
const RESIDENT_GENDER := 0x0014
const RESIDENT_FACE := 0x0015
const RESIDENT_POCKETS := 0x0068
const RESIDENT_POCKET_CONDITIONS := 0x0088
const RESIDENT_WALLET := 0x008C
const RESIDENT_LOAN := 0x0090
const RESIDENT_CLOTH := 0x108A
const RESIDENT_SAVINGS := 0x122C
const POCKET_NUM := 15
const NAME_LEN := 8
## `mHm_hs_c`: `flags`, `size_info` (size:3 next_size:3 statue_rank:2), `outlook_pal`.
const HOME_FLAGS := 0x24
const HOME_SIZE_BITS := 0x2A
const HOME_ROOF := 0x2C
## `Animal_c`: `id.npc_id`, `home_info` {type, block_x, block_z, ut_x, ut_z}, `cloth`, `moved_in`.
const VILLAGER_NPC_ID := 0x000
const VILLAGER_HOME := 0x899
const VILLAGER_CLOTH := 0x8E4
const VILLAGER_MOVED_IN := 0x8E9
## `NAME_TYPE_NPC` in the top nibble of a villager's id.
const NPC_NAME_TYPE := 0xE
## `mLd_CHECK_LAND_ID`: a resident's land id carries 0x30 in its high byte.
const LAND_ID_MARK := 0x3000

const CHARSET_PATH := "res://tools/asset_pipeline/ac_msg_codec.json"
static var _charset: PackedStringArray = PackedStringArray()


static func decode(file: PackedByteArray) -> Dictionary:
	var base: int = find_save(file)
	if base < 0:
		return {}
	var out: Dictionary = {
		"town_name": text(file, base + LAND_NAME, NAME_LEN),
		"town_id": GameCubeCard.u16(file, base + LAND_ID),
		"saved_at": _time(file, base + CHECK_TIME),
		"fruit": GameCubeCard.u16(file, base + FRUIT),
		"tune": _tune(file, base + TUNE),
		"grass_pattern": file[base + GRASS_PATTERN],
		"statues": file[base + STATUES],
		"villager_max": file[base + VILLAGER_MAX],
	}
	var acres: Array[int] = []
	for i: int in BLOCK_NUM:
		acres.append(GameCubeCard.u16(file, base + ACRES + i * 2))
	out["acres"] = acres
	var field: Array[PackedInt32Array] = []
	var buried: Array[PackedInt32Array] = []
	for acre: int in FIELD_X * FIELD_Z:
		var items := PackedInt32Array()
		items.resize(UNITS * UNITS)
		for i: int in UNITS * UNITS:
			items[i] = GameCubeCard.u16(file, base + FIELD + (acre * UNITS * UNITS + i) * 2)
		field.append(items)
		var rows := PackedInt32Array()
		rows.resize(UNITS)
		for z: int in UNITS:
			rows[z] = GameCubeCard.u16(file, base + BURIED + (acre * UNITS + z) * 2)
		buried.append(rows)
	out["field"] = field
	out["buried"] = buried
	var arrangement: int = file[base + HOUSE_ARRANGEMENT]
	var residents: Array[Dictionary] = []
	for i: int in RESIDENT_NUM:
		var house_index: int = (arrangement >> (i * 2)) & 3
		residents.append(_resident(file, base + RESIDENTS + i * RESIDENT_SIZE, base + HOMES + house_index * HOME_SIZE, house_index))
	out["residents"] = residents
	var villagers: Array[Dictionary] = []
	for i: int in VILLAGER_NUM:
		villagers.append(_villager(file, base + VILLAGERS + i * VILLAGER_SIZE))
	out["villagers"] = villagers
	return out


## Offset of the first copy in the town file that passes the save check, or -1.
static func find_save(file: PackedByteArray) -> int:
	for offset: int in SAVE_OFFSETS:
		if is_valid_save(file, offset):
			return offset
	return -1


## `mCD_LoadLand`'s check: the game code, a known version, and every big-endian u16 of the
## save summing to zero (`mFRm_ReturnCheckSum`).
static func is_valid_save(file: PackedByteArray, offset: int) -> bool:
	if offset < 0 or offset + SAVE_SIZE > file.size():
		return false
	if GameCubeCard.u32(file, offset + CHECK_CODE) != SAVE_CODE:
		return false
	if not SAVE_VERSIONS.has(GameCubeCard.u32(file, offset + CHECK_VERSION)):
		return false
	return checksum(file, offset) == 0


static func checksum(file: PackedByteArray, offset: int) -> int:
	var sum: int = 0
	for i: int in range(offset, offset + SAVE_SIZE, 2):
		sum += (file[i] << 8) | file[i + 1]
	return sum & 0xFFFF


## A name in the game's font encoding, without its trailing space padding.
static func text(file: PackedByteArray, offset: int, length: int) -> String:
	_ensure_charset()
	var out := ""
	for i: int in length:
		var code: int = file[offset + i]
		out += _charset[code] if _charset.size() == 256 else char(code)
	return out.rstrip(" ")


static func _resident(file: PackedByteArray, at: int, home: int, house_index: int) -> Dictionary:
	if (GameCubeCard.u16(file, at + RESIDENT_LAND_ID) & 0xFF00) != LAND_ID_MARK:
		return {}
	var conditions: int = GameCubeCard.u32(file, at + RESIDENT_POCKET_CONDITIONS)
	var pockets: Array[Dictionary] = []
	for i: int in POCKET_NUM:
		pockets.append({
			"item": GameCubeCard.u16(file, at + RESIDENT_POCKETS + i * 2),
			"condition": (conditions >> (i * 2)) & 3,
		})
	var size_bits: int = file[home + HOME_SIZE_BITS]
	return {
		"name": text(file, at + RESIDENT_NAME, NAME_LEN),
		"gender": file[at + RESIDENT_GENDER],
		"face": file[at + RESIDENT_FACE],
		"wallet": GameCubeCard.u32(file, at + RESIDENT_WALLET),
		"savings": GameCubeCard.u32(file, at + RESIDENT_SAVINGS),
		"loan": GameCubeCard.u32(file, at + RESIDENT_LOAN),
		"cloth": GameCubeCard.u16(file, at + RESIDENT_CLOTH),
		"pockets": pockets,
		"house": {
			"plot": house_index,
			"size": size_bits >> 5,
			"next_size": (size_bits >> 2) & 7,
			"statue_rank": size_bits & 3,
			"has_basement": ((file[home + HOME_FLAGS] >> 4) & 1) == 1,
			"roof": file[home + HOME_ROOF],
		},
	}


static func _villager(file: PackedByteArray, at: int) -> Dictionary:
	var npc_id: int = GameCubeCard.u16(file, at + VILLAGER_NPC_ID)
	if (npc_id >> 12) != NPC_NAME_TYPE:
		return {}
	## `home_info` counts acres from the map border (block 1 is the first field acre) and
	## stands one unit south of the SIGN unit the house sits on (`mNpc_SetNpcHome`).
	var block_x: int = file[at + VILLAGER_HOME]
	var block_z: int = file[at + VILLAGER_HOME + 1]
	var home := NO_HOME
	if block_x != 0xFF and block_z != 0xFF and block_x >= 1 and block_z >= 1:
		home = Vector2i(
			(block_x - 1) * UNITS + file[at + VILLAGER_HOME + 2],
			(block_z - 1) * UNITS + file[at + VILLAGER_HOME + 3] - 1
		)
	return {
		"npc_index": npc_id & 0xFFF,
		"home": home,
		"moved_in": file[at + VILLAGER_MOVED_IN] != 0,
		"cloth": GameCubeCard.u16(file, at + VILLAGER_CLOTH),
	}


## `lbRTC_time_c`: sec, min, hour, day, weekday, month, year (u16).
static func _time(file: PackedByteArray, at: int) -> Dictionary:
	return {
		"second": file[at],
		"minute": file[at + 1],
		"hour": file[at + 2],
		"day": file[at + 3],
		"month": file[at + 5],
		"year": GameCubeCard.u16(file, at + 6),
	}


## `Save_Get(melody)`: a u64 of 16 nibbles, first note on top (`mMld_TransformMelodyData_u64_2_u8`).
static func _tune(file: PackedByteArray, at: int) -> PackedByteArray:
	var notes := PackedByteArray()
	for i: int in 8:
		notes.append(file[at + i] >> 4)
		notes.append(file[at + i] & 0xF)
	return notes


static func _ensure_charset() -> void:
	if not _charset.is_empty() or not FileAccess.file_exists(CHARSET_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CHARSET_PATH))
	if parsed is Dictionary and (parsed as Dictionary).get("char_map") is Array:
		_charset = PackedStringArray((parsed as Dictionary)["char_map"] as Array)
