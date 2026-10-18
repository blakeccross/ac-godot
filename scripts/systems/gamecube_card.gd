class_name GameCubeCard
extends RefCounted

## Finds the Animal Crossing town file on a GameCube Memory Card dump. Two shapes are read:
## a single exported file (`.gci`, Dolphin's GCI folder or its Memory Card Manager export:
## a 64-byte directory entry and then the file's blocks), and a whole card image (`.raw`,
## Dolphin's default card: header, two directory copies, two block-allocation-table copies,
## then 8 KiB blocks chained through the table). Everything on the card is big-endian.

const BLOCK_SIZE := 0x2000
const ENTRY_SIZE := 0x40
## Card blocks 0–4: header, directory, directory backup, allocation table, table backup.
const FIRST_DATA_BLOCK := 5
const ENTRIES_PER_DIRECTORY := 127
## Each directory / allocation table copy keeps an update counter; the higher one is current.
const DIRECTORY_COUNTER := 0x1FFA
const TABLE_COUNTER := 0x04
const TABLE_MAP := 0x0A
const LAST_BLOCK := 0xFFFF
## `mCD_file_name` (`m_card.c`) and the USA game code (`mFRm_SAVE_ID`).
const TOWN_FILE_NAME := "DobutsunomoriP_MURA"
const GAME_CODE := "GAFE"
## `CARDDir` fields inside a directory entry.
const ENTRY_FILE_NAME := 0x08
const ENTRY_FIRST_BLOCK := 0x36
const ENTRY_BLOCK_COUNT := 0x38


## The town file's own bytes (no directory entry) from a `.gci` or a card image, or empty.
static func town_file(bytes: PackedByteArray) -> PackedByteArray:
	if _is_town_entry(bytes, 0):
		return _gci_data(bytes)
	return _card_image_data(bytes)


static func u16(buf: PackedByteArray, offset: int) -> int:
	return (buf[offset] << 8) | buf[offset + 1]


static func u32(buf: PackedByteArray, offset: int) -> int:
	return (buf[offset] << 24) | (buf[offset + 1] << 16) | (buf[offset + 2] << 8) | buf[offset + 3]


static func _gci_data(bytes: PackedByteArray) -> PackedByteArray:
	var blocks: int = u16(bytes, ENTRY_BLOCK_COUNT)
	var size: int = mini(blocks * BLOCK_SIZE, bytes.size() - ENTRY_SIZE)
	return bytes.slice(ENTRY_SIZE, ENTRY_SIZE + size)


static func _card_image_data(bytes: PackedByteArray) -> PackedByteArray:
	if bytes.size() < FIRST_DATA_BLOCK * BLOCK_SIZE or bytes.size() % BLOCK_SIZE != 0:
		return PackedByteArray()
	var directory: int = _current_copy(bytes, 1, DIRECTORY_COUNTER)
	var table: int = _current_copy(bytes, 3, TABLE_COUNTER)
	for i: int in ENTRIES_PER_DIRECTORY:
		var entry: int = directory + i * ENTRY_SIZE
		if not _is_town_entry(bytes, entry):
			continue
		var out := PackedByteArray()
		var block: int = u16(bytes, entry + ENTRY_FIRST_BLOCK)
		for _n: int in u16(bytes, entry + ENTRY_BLOCK_COUNT):
			var start: int = block * BLOCK_SIZE
			if block < FIRST_DATA_BLOCK or start + BLOCK_SIZE > bytes.size():
				return PackedByteArray()
			out.append_array(bytes.slice(start, start + BLOCK_SIZE))
			block = u16(bytes, table + TABLE_MAP + (block - FIRST_DATA_BLOCK) * 2)
			if block == LAST_BLOCK:
				break
		return out
	return PackedByteArray()


## Byte offset of whichever of blocks `first` / `first + 1` was written last.
static func _current_copy(bytes: PackedByteArray, first: int, counter: int) -> int:
	var a: int = first * BLOCK_SIZE
	var b: int = a + BLOCK_SIZE
	return b if _s16(u16(bytes, b + counter)) > _s16(u16(bytes, a + counter)) else a


static func _s16(v: int) -> int:
	return v - 0x10000 if v >= 0x8000 else v


static func _is_town_entry(bytes: PackedByteArray, offset: int) -> bool:
	if offset + ENTRY_SIZE > bytes.size():
		return false
	if _c_string(bytes, offset, 4) != GAME_CODE:
		return false
	return _c_string(bytes, offset + ENTRY_FILE_NAME, 32) == TOWN_FILE_NAME


static func _c_string(bytes: PackedByteArray, offset: int, length: int) -> String:
	var raw: PackedByteArray = bytes.slice(offset, offset + length)
	var end: int = raw.find(0)
	return (raw.slice(0, end) if end >= 0 else raw).get_string_from_ascii()
