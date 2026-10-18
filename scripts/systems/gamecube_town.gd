class_name GameCubeTown
extends RefCounted

## Reads a GameCube town save (`Save_t`, `m_common_data.h`) out of the Memory Card town file
## (`GameCubeCard.town_file`) into plain values for `TownImport`. USA release (`GAFE`),
## save versions 5 and 6. Island FG and event blobs that this port has no system for are
## left unread.

## The town file holds three 0x26000-byte `Save` areas (`l_mcd_file_table`): the first opens
## with the card comment, banner and icon and keeps letters, designs and the diary; the second
## is the save (`mCD_FILE_SAVE_MAIN`), the third its backup (`mCD_FILE_SAVE_MAIN_BAK`).
const SAVE_SIZE := 0x26000
const SAVE_OFFSETS: Array[int] = [SAVE_SIZE, SAVE_SIZE * 2, 0]
const SAVE_CODE := 0x47414645
const SAVE_VERSIONS: Array[int] = [5, 6]
const RESIDENT_NUM := 4
const VILLAGER_NUM := 15
const FIELD_X := 5
const FIELD_Z := 6
const UNITS := 16
const BLOCK_NUM := 70
const NO_HOME := Vector2i(-1, -1)
const FREE_ID := 0xFFFF
const LAND_ID_MARK := 0x3000
const NPC_NAME_TYPE := 0xE
const NAME_LEN := 8
const POCKET_NUM := 15
const ROOM_NUM := 3
const LAYER_NUM := 4
const DESIGN_NUM := 8
const DESIGN_SIZE := 0x220
const DESIGN_NAME_LEN := 16
const DESIGN_TEX := 0x20
const DESIGN_TEX_SIZE := 512
const MAIL_SIZE := 0x12A
const MAIL_POCKET_NUM := 10
const MAIL_HOME_NUM := 10
const MAIL_POST_NUM := 5
const NOTICE_NUM := 15
const NOTICE_SIZE := 0xC8
const GOODS_COUNT := 39
const LOTTERY_COUNT := 3
const POLICE_COUNT := 20
const FISH_RECORD_NUM := 5
const FISH_RECORD_SIZE := 0x20
const CATALOG_ORDER_NUM := 5
const FURNITURE_BITS := 43
const WALL_BITS := 3
const CARPET_BITS := 3
const PAPER_BITS := 2
const MUSIC_BITS := 2
const INSECT_BIT0 := 0x2F2

## `mFRm_chk_t` / `Save_t`.
const CHECK_VERSION := 0x00
const CHECK_CODE := 0x04
const CHECK_TIME := 0x0A
const VILLAGER_MAX := 0x18
const RESIDENTS := 0x20
const RESIDENT_SIZE := 0x2440
const NOTICE := 0x912C
const LAND_NAME := 0x9120
const LAND_ID := 0x912A
const HOMES := 0x9CE8
const HOME_SIZE := 0x26B0
const FIELD := 0x137A8
const ACRES := 0x173A8
const VILLAGERS := 0x17438
const VILLAGER_SIZE := 0x988
const SHOP := 0x20340
const STALK := 0x20480
const FRUIT := 0x20688
const HOUSE_ARRANGEMENT := 0x2068A
const STATUES := 0x2068B
const POST := 0x20694
const POLICE := 0x20ED0
const SNOWMEN := 0x20EF8
const TUNE := 0x20F08
const WEATHER := 0x20F19
const BURIED := 0x20F1C
const HANIWA_SCHED := 0x21393
const DUST_FLAG := 0x21394
const CLEAR_GRASS := 0x21395
const MUSEUM := 0x213A8
const BRIDGE := 0x213F0
const NEEDLEWORK := 0x21400
const FISH_RECORDS := 0x23E68
const LIGHTHOUSE := 0x2416C
const INSECT_TERM := 0x24174
const FISH_TERM := 0x24176
const PERFECT_STREAK := 0x24180
const GRASS_PATTERN := 0x24184
const RAINBOW_MONTH := 0x24185
const RAINBOW_DAY := 0x24186
const RAINBOW_RESERVED := 0x24187

## `Private_c`.
const RESIDENT_NAME := 0x0000
const RESIDENT_PLAYER_ID := 0x0010
const RESIDENT_LAND_ID := 0x0012
const RESIDENT_GENDER := 0x0014
const RESIDENT_FACE := 0x0015
const RESIDENT_POCKETS := 0x0068
const RESIDENT_POCKET_CONDITIONS := 0x0088
const RESIDENT_WALLET := 0x008C
const RESIDENT_LOAN := 0x0090
const RESIDENT_MAIL := 0x04E0
const RESIDENT_CLOTH := 0x108A
const RESIDENT_CATALOG_ORDERS := 0x10A8
const RESIDENT_FURNITURE_BITS := 0x1108
const RESIDENT_WALL_BITS := 0x11B4
const RESIDENT_CARPET_BITS := 0x11C0
const RESIDENT_PAPER_BITS := 0x11CC
const RESIDENT_MUSIC_BITS := 0x11D4
const RESIDENT_SAVINGS := 0x122C
const RESIDENT_DESIGNS := 0x1240
const RESIDENT_DESIGN_ORDER := 0x2340
const RESIDENT_SABLE := 0x23B8

## `mHm_hs_c`.
const HOME_FLAGS := 0x24
## `mHm_rmsz_c` at 0x26: order ymd, then packed size byte, then flag byte.
const HOME_SIZE_INFO := 0x26
const HOME_SIZE_BITS := 0x2A
const HOME_SIZE_FLAGS := 0x2B
const HOME_ROOF := 0x2C
const HOME_ORDERED_ROOF := 0x2D
const HOME_NEXT_ROOF := 0x2E
const HOME_FLOORS := 0x38
const FLOOR_SIZE := 0x8A8
const LAYER_SIZE := 0x228
const WALL_FLOOR := 0x8A0
const HOME_MAILBOX := 0x1A30
const HOME_HANIWA := 0x25D4
const HOME_GOKI := 0x2678
const HOME_MUSIC := 0x2684
const HANIWA_ITEM_NUM := 4
const HANIWA_ITEM_SIZE := 8
const HANIWA_MSG_LEN := 128

## `Animal_c`.
const VILLAGER_NPC_ID := 0x000
const VILLAGER_MEMORIES := 0x010
const MEMORY_SIZE := 0x138
const MEMORY_NUM := 7
const MEMORY_PLAYER_ID := 0x10
const MEMORY_LAND_ID := 0x12
const MEMORY_LAST_SPEAK := 0x14
const MEMORY_FRIENDSHIP := 0x30
const MEMORY_LETTER_INFO := 0x31
const VILLAGER_HOME := 0x899
const VILLAGER_CLOTH := 0x8E4
const VILLAGER_MOVED_IN := 0x8E9

## `Shop_c` / `PostOffice_c` / `Mail_c`.
const SHOP_ITEMS := 0xCE
const SHOP_RARE := 0x11C
const SHOP_LOTTERY := 0x11E
const SHOP_INFO := 0x126
const SHOP_SALES := 0x128
const SHOP_EXCHANGE := 0x12C
const SHOP_RENEWAL := 0x134
const SHOP_VISITOR := 0x13C
const POST_KEEP_PLAYERS := 0x00
const POST_KEEP_NPCS := 0x02
const POST_MAIL := 0x08
const POST_DELIVERY := 0x834
const MAIL_PRESENT := 0x2C
const MAIL_FONT := 0x2E
const MAIL_PAPER := 0x31
const MAIL_HEADER := 0x32
const MAIL_BODY := 0x4A
const MAIL_FOOTER := 0x10A
const MAIL_HEADER_LEN := 24
const MAIL_BODY_LEN := 192
const MAIL_FOOTER_LEN := 32
const MAIL_NAME_TYPE := 0x14

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
		"weather": file[base + WEATHER],
		"clear_grass": file[base + CLEAR_GRASS] != 0,
		"dust_flag": file[base + DUST_FLAG] != 0,
		"gyroids_scheduled": file[base + HANIWA_SCHED] != 0,
		"perfect_streak": GameCubeCard.u32(file, base + PERFECT_STREAK),
		"fish_term": file[base + FISH_TERM],
		"fish_term_offset": file[base + FISH_TERM + 1],
		"insect_term": file[base + INSECT_TERM],
		"insect_term_offset": file[base + INSECT_TERM + 1],
		"rainbow": {
			"reserved": file[base + RAINBOW_RESERVED] != 0,
			"month": file[base + RAINBOW_MONTH],
			"day": file[base + RAINBOW_DAY],
		},
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
	out["museum"] = _bytes(file, base + MUSEUM, 0x3F)
	out["shop"] = _shop(file, base + SHOP)
	out["stalk"] = _stalk(file, base + STALK)
	out["police"] = _item_list(file, base + POLICE, POLICE_COUNT)
	out["post"] = _post(file, base + POST)
	out["notice"] = _notice(file, base + NOTICE)
	out["lighthouse"] = _lighthouse(file, base + LIGHTHOUSE)
	out["bridge"] = _bridge(file, base + BRIDGE)
	out["snowmen"] = _snowmen(file, base + SNOWMEN)
	out["fish_records"] = _fish_records(file, base + FISH_RECORDS)
	out["designs_shop"] = _designs(file, base + NEEDLEWORK, DESIGN_NUM)
	return out


static func find_save(file: PackedByteArray) -> int:
	for offset: int in SAVE_OFFSETS:
		if is_valid_save(file, offset):
			return offset
	return -1


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


static func text(file: PackedByteArray, offset: int, length: int) -> String:
	_ensure_charset()
	var out := ""
	for i: int in length:
		var code: int = file[offset + i]
		## Zero-padded fields (design names, notice bodies) end at the first NUL.
		if code == 0:
			break
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
	var size_flags: int = file[home + HOME_SIZE_FLAGS]
	var order_at: int = home + HOME_SIZE_INFO
	var orders: Array[Dictionary] = []
	for i: int in CATALOG_ORDER_NUM:
		var o: int = at + RESIDENT_CATALOG_ORDERS + i * 4
		orders.append({"item": GameCubeCard.u16(file, o), "level": file[o + 2]})
	var order_table: Array[int] = []
	for i: int in DESIGN_NUM:
		order_table.append(file[at + RESIDENT_DESIGN_ORDER + i])
	var sable: int = at + RESIDENT_SABLE
	return {
		"name": text(file, at + RESIDENT_NAME, NAME_LEN),
		"player_id": GameCubeCard.u16(file, at + RESIDENT_PLAYER_ID),
		"land_id": GameCubeCard.u16(file, at + RESIDENT_LAND_ID),
		"gender": file[at + RESIDENT_GENDER],
		"face": file[at + RESIDENT_FACE],
		"wallet": GameCubeCard.u32(file, at + RESIDENT_WALLET),
		"savings": GameCubeCard.u32(file, at + RESIDENT_SAVINGS),
		"loan": GameCubeCard.u32(file, at + RESIDENT_LOAN),
		"cloth": GameCubeCard.u16(file, at + RESIDENT_CLOTH),
		"pockets": pockets,
		"mail": _mails(file, at + RESIDENT_MAIL, MAIL_POCKET_NUM),
		"designs": _designs(file, at + RESIDENT_DESIGNS, DESIGN_NUM),
		"design_order": order_table,
		"catalog_orders": orders,
		"furniture_bits": _u32s(file, at + RESIDENT_FURNITURE_BITS, FURNITURE_BITS),
		"wall_bits": _u32s(file, at + RESIDENT_WALL_BITS, WALL_BITS),
		"carpet_bits": _u32s(file, at + RESIDENT_CARPET_BITS, CARPET_BITS),
		"paper_bits": _u32s(file, at + RESIDENT_PAPER_BITS, PAPER_BITS),
		"music_bits": _u32s(file, at + RESIDENT_MUSIC_BITS, MUSIC_BITS),
		## `mPr_day_day_c`: ymd then unique-day count.
		"sable_days": file[sable + 4],
		"sable_date": {
			"year": GameCubeCard.u16(file, sable),
			"month": file[sable + 2],
			"day": file[sable + 3],
		},
		"house": {
			"plot": house_index,
			"size": size_bits >> 5,
			"next_size": (size_bits >> 2) & 7,
			"statue_rank": size_bits & 3,
			## `mHm_rmsz_c` flag byte (MSB-first): renew / statue_ordered / basement_ordered.
			"renew": ((size_flags >> 7) & 1) == 1,
			"statue_ordered": ((size_flags >> 6) & 1) == 1,
			"basement_ordered": ((size_flags >> 5) & 1) == 1,
			"order_day": file[order_at],
			"order_month": file[order_at + 1],
			"order_year": GameCubeCard.u16(file, order_at + 2),
			"has_basement": ((file[home + HOME_FLAGS] >> 4) & 1) == 1,
			"has_saved": ((file[home + HOME_FLAGS] >> 6) & 1) == 1,
			"roof": file[home + HOME_ROOF],
			"ordered_roof": file[home + HOME_ORDERED_ROOF],
			"next_roof": file[home + HOME_NEXT_ROOF],
			"music_box": _u64(file, home + HOME_MUSIC),
			"goki_count": file[home + HOME_GOKI + 8],
			"goki_time": _time(file, home + HOME_GOKI),
			"gyroid": _gyroid(file, home + HOME_HANIWA),
			"mailbox": _mails(file, home + HOME_MAILBOX, MAIL_HOME_NUM),
		},
		"rooms": _rooms(file, home),
	}


static func _villager(file: PackedByteArray, at: int) -> Dictionary:
	var npc_id: int = GameCubeCard.u16(file, at + VILLAGER_NPC_ID)
	if (npc_id >> 12) != NPC_NAME_TYPE:
		return {}
	var block_x: int = file[at + VILLAGER_HOME]
	var block_z: int = file[at + VILLAGER_HOME + 1]
	var home := NO_HOME
	if block_x != 0xFF and block_z != 0xFF and block_x >= 1 and block_z >= 1:
		home = Vector2i(
			(block_x - 1) * UNITS + file[at + VILLAGER_HOME + 2],
			(block_z - 1) * UNITS + file[at + VILLAGER_HOME + 3] - 1
		)
	var memories: Array[Dictionary] = []
	for i: int in MEMORY_NUM:
		var mem: Dictionary = _memory(file, at + VILLAGER_MEMORIES + i * MEMORY_SIZE)
		if not mem.is_empty():
			memories.append(mem)
	return {
		"npc_index": npc_id & 0xFFF,
		"home": home,
		"moved_in": file[at + VILLAGER_MOVED_IN] != 0,
		"cloth": GameCubeCard.u16(file, at + VILLAGER_CLOTH),
		"memories": memories,
	}


## Four FG layers + switch bitfields per room (`mHm_flr_c`).
static func _rooms(file: PackedByteArray, home: int) -> Array[Dictionary]:
	var rooms: Array[Dictionary] = []
	for r: int in ROOM_NUM:
		var floor_at: int = home + HOME_FLOORS + r * FLOOR_SIZE
		var layers: Array[PackedInt32Array] = []
		var switches: Array[int] = []
		for layer: int in LAYER_NUM:
			var at: int = floor_at + layer * LAYER_SIZE
			var items := PackedInt32Array()
			items.resize(UNITS * UNITS)
			for i: int in UNITS * UNITS:
				items[i] = GameCubeCard.u16(file, at + i * 2)
			layers.append(items)
			if layer < 2:
				switches.append(_u64(file, at + 0x200))
		var wf: int = floor_at + WALL_FLOOR
		rooms.append({
			"floor_idx": file[wf],
			"wall_idx": file[wf + 1],
			"layers": layers,
			"switches": switches,
		})
	return rooms


static func _memory(file: PackedByteArray, at: int) -> Dictionary:
	var land_id: int = GameCubeCard.u16(file, at + MEMORY_LAND_ID)
	if land_id == FREE_ID or (land_id & 0xFF00) != LAND_ID_MARK:
		return {}
	var letter: int = file[at + MEMORY_LETTER_INFO]
	var friendship: int = file[at + MEMORY_FRIENDSHIP]
	if friendship >= 0x80:
		friendship -= 0x100
	return {
		"name": text(file, at, NAME_LEN),
		"player_id": GameCubeCard.u16(file, at + MEMORY_PLAYER_ID),
		"land_id": land_id,
		"friendship": friendship,
		"last_spoke": _time(file, at + MEMORY_LAST_SPEAK),
		"letter_exists": (letter & 0x80) != 0,
		"letter_cond": 1 if (letter & 0x40) != 0 else 0,
		"send_reply": (letter & 0x20) != 0,
	}


static func _shop(file: PackedByteArray, at: int) -> Dictionary:
	var goods: Array[int] = []
	for i: int in GOODS_COUNT:
		goods.append(GameCubeCard.u16(file, at + SHOP_ITEMS + i * 2))
	var lottery: Array[int] = []
	for i: int in LOTTERY_COUNT:
		lottery.append(GameCubeCard.u16(file, at + SHOP_LOTTERY + i * 2))
	var info: int = GameCubeCard.u16(file, at + SHOP_INFO)
	return {
		"goods": goods,
		"rare": GameCubeCard.u16(file, at + SHOP_RARE),
		"lottery": lottery,
		"level": (info >> 14) & 3,
		"upgrading": ((info >> 13) & 1) == 1,
		"paint": (info >> 7) & 0xF,
		"sales": GameCubeCard.u32(file, at + SHOP_SALES),
		"exchange": _time(file, at + SHOP_EXCHANGE),
		"renewal": _time(file, at + SHOP_RENEWAL),
		"visitor": GameCubeCard.u32(file, at + SHOP_VISITOR) != 0,
	}


static func _stalk(file: PackedByteArray, at: int) -> Dictionary:
	var prices: Array[int] = []
	for i: int in 7:
		prices.append(GameCubeCard.u16(file, at + i * 2))
	return {
		"prices": prices,
		"trend": GameCubeCard.u16(file, at + 0x0E),
		"update": _time(file, at + 0x10),
	}


static func _post(file: PackedByteArray, at: int) -> Dictionary:
	return {
		"keep_mail_sum_players": _s16(GameCubeCard.u16(file, at + POST_KEEP_PLAYERS)),
		"keep_mail_sum_npcs": _s16(GameCubeCard.u16(file, at + POST_KEEP_NPCS)),
		"mail": _mails(file, at + POST_MAIL, MAIL_POST_NUM),
		"delivery": _time(file, at + POST_DELIVERY),
	}


static func _notice(file: PackedByteArray, at: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in NOTICE_NUM:
		var p: int = at + i * NOTICE_SIZE
		var msg: String = text(file, p, MAIL_BODY_LEN)
		if msg == "":
			continue
		out.append({"text": msg, "time": _time(file, p + 0xC0)})
	return out


static func _lighthouse(file: PackedByteArray, at: int) -> Dictionary:
	return {
		"year": GameCubeCard.u16(file, at),
		"month": file[at + 2],
		"day": file[at + 3],
		"nights": file[at + 4],
		"taken": file[at + 5],
		"completed": file[at + 6],
	}


static func _bridge(file: PackedByteArray, at: int) -> Dictionary:
	var flags: int = file[at + 2]
	return {
		"bx": file[at],
		"bz": file[at + 1],
		"exists": (flags & 0x80) != 0,
		"pending": (flags & 0x40) != 0,
		"build": {"year": GameCubeCard.u16(file, at + 4), "month": file[at + 6], "day": file[at + 7]},
	}


static func _snowmen(file: PackedByteArray, at: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in 3:
		var p: int = at + i * 4
		if file[p] == 0:
			out.append({})
			continue
		out.append({
			"head": file[p + 1],
			"body": file[p + 2],
			"score": file[p + 3],
		})
	return out


static func _fish_records(file: PackedByteArray, at: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in FISH_RECORD_NUM:
		var p: int = at + i * FISH_RECORD_SIZE
		var land_id: int = GameCubeCard.u16(file, p + 0x12)
		if land_id == FREE_ID or (land_id & 0xFF00) != LAND_ID_MARK:
			continue
		out.append({
			"name": text(file, p, NAME_LEN),
			"time": _time(file, p + 0x14),
			"size": GameCubeCard.u32(file, p + 0x1C),
		})
	return out


static func _designs(file: PackedByteArray, at: int, count: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in count:
		var p: int = at + i * DESIGN_SIZE
		var tex := PackedByteArray()
		tex.resize(DESIGN_TEX_SIZE)
		for b: int in DESIGN_TEX_SIZE:
			tex[b] = file[p + DESIGN_TEX + b]
		out.append({
			"name": text(file, p, DESIGN_NAME_LEN),
			"palette": file[p + 0x10] & 0xF,
			"flag": file[p + 0x11] != 0,
			"ci4": tex,
		})
	return out


static func _mails(file: PackedByteArray, at: int, count: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in count:
		var mail: Dictionary = _mail(file, at + i * MAIL_SIZE)
		if not mail.is_empty():
			out.append(mail)
		else:
			out.append({})
	return out


static func _mail(file: PackedByteArray, at: int) -> Dictionary:
	var recip_type: int = file[at + MAIL_NAME_TYPE]
	var sender_type: int = file[at + 0x16 + MAIL_NAME_TYPE]
	if recip_type == 0xFF and sender_type == 0xFF:
		return {}
	var recip_name: String = text(file, at, NAME_LEN)
	var sender_name: String = text(file, at + 0x16, NAME_LEN)
	if recip_name == "" and sender_name == "" and GameCubeCard.u16(file, at + MAIL_PRESENT) == 0:
		return {}
	return {
		"recipient_name": recip_name,
		"recipient_type": recip_type,
		"recipient_npc": GameCubeCard.u16(file, at + 0x10) if recip_type == 1 else 0,
		"sender_name": sender_name,
		"sender_type": sender_type,
		"sender_npc": GameCubeCard.u16(file, at + 0x16 + 0x10) if sender_type == 1 else 0,
		"present": GameCubeCard.u16(file, at + MAIL_PRESENT),
		"font": file[at + MAIL_FONT],
		"paper": file[at + MAIL_PAPER],
		"header": text(file, at + MAIL_HEADER, MAIL_HEADER_LEN),
		"body": text(file, at + MAIL_BODY, MAIL_BODY_LEN),
		"footer": text(file, at + MAIL_FOOTER, MAIL_FOOTER_LEN),
	}


static func _gyroid(file: PackedByteArray, at: int) -> Dictionary:
	var items: Array[Dictionary] = []
	for i: int in HANIWA_ITEM_NUM:
		var p: int = at + i * HANIWA_ITEM_SIZE
		items.append({
			"item": GameCubeCard.u16(file, p),
			"exchange": _s16(GameCubeCard.u16(file, p + 2)),
			"extra": GameCubeCard.u32(file, p + 4),
		})
	return {
		"items": items,
		"message": text(file, at + 0x20, HANIWA_MSG_LEN),
		"bells": GameCubeCard.u32(file, at + 0xA0),
	}


static func _item_list(file: PackedByteArray, at: int, count: int) -> Array[int]:
	var out: Array[int] = []
	for i: int in count:
		out.append(GameCubeCard.u16(file, at + i * 2))
	return out


static func _bytes(file: PackedByteArray, at: int, count: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(count)
	for i: int in count:
		out[i] = file[at + i]
	return out


static func _u32s(file: PackedByteArray, at: int, count: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(count)
	for i: int in count:
		out[i] = GameCubeCard.u32(file, at + i * 4)
	return out


static func _u64(file: PackedByteArray, at: int) -> int:
	return (GameCubeCard.u32(file, at) << 32) | GameCubeCard.u32(file, at + 4)


static func _s16(v: int) -> int:
	return v if v < 0x8000 else v - 0x10000


static func _time(file: PackedByteArray, at: int) -> Dictionary:
	return {
		"second": file[at],
		"minute": file[at + 1],
		"hour": file[at + 2],
		"day": file[at + 3],
		"month": file[at + 5],
		"year": GameCubeCard.u16(file, at + 6),
	}


static func _ymd(t: Dictionary) -> Vector3i:
	return Vector3i(int(t.get("year", 0)), int(t.get("month", 0)), int(t.get("day", 0)))


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
