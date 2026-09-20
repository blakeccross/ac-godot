class_name MinidiskCatalog
extends RefCounted

## The 55 K.K. records (`ITM_MINIDISK00`…`54`, `MINIDISK_NUM`). A disc put in a music player is
## added to the house's music box (`House.music_box`) and consumed; the box then plays any of its
## songs without a disc. Song `i` plays `BGM_MD0 + i` (bgm number 128 + i).
##
## Titles are placeholders until the disc's item-name table is extracted.

const COUNT := 55
const ID_PREFIX := "minidisk_"
## `BGM_MD0`.
const BGM_FIRST := 128


static func item_id(index: int) -> StringName:
	return StringName("%s%02d" % [ID_PREFIX, clampi(index, 0, COUNT - 1)])


static func index_of(item_id_: StringName) -> int:
	var raw := String(item_id_)
	if not raw.begins_with(ID_PREFIX):
		return -1
	var tail: String = raw.substr(ID_PREFIX.length())
	if not tail.is_valid_int():
		return -1
	var index: int = int(tail)
	return index if index >= 0 and index < COUNT else -1


static func is_disc(item_id_: StringName) -> bool:
	return index_of(item_id_) >= 0


static func song_name(index: int) -> String:
	return "K.K. Song %02d" % (clampi(index, 0, COUNT - 1) + 1)


static func bgm_id(index: int) -> StringName:
	return BgmCatalog.id_for_num(BGM_FIRST + clampi(index, 0, COUNT - 1))


## Register every disc as an ordinary pocket item (`ItemCatalog.ensure_loaded`).
static func register_items() -> void:
	for i: int in COUNT:
		var data := ItemData.new()
		data.id = item_id(i)
		data.display_name = song_name(i)
		data.category = ItemData.Category.OTHER
		data.max_stack = 1
		data.droppable = true
		data.usable = false
		data.sell_price = 0
		data.icon_color = Color(0.35, 0.35, 0.45)
		ItemCatalog.remember(data)


## --- House music box ----------------------------------------------------------------------


static func box_has(house: House, index: int) -> bool:
	return house != null and index >= 0 and index < COUNT and ((house.music_box >> index) & 1) == 1


static func box_add(house: House, index: int) -> bool:
	if house == null or index < 0 or index >= COUNT or box_has(house, index):
		return false
	house.music_box |= 1 << index
	return true


static func box_songs(house: House) -> Array[int]:
	var out: Array[int] = []
	for i: int in COUNT:
		if box_has(house, i):
			out.append(i)
	return out
