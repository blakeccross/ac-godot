class_name MuseumBook
extends RefCounted

## Town museum display bits (`mMmd_info_c`). Owned by `Game`, not an autoload.
## Each slot packs a 4-bit donator id (two slots per byte).

enum DisplayInfo { CANNOT_DONATE, CAN_DONATE, ALREADY_DONATED }
enum Donator { NONE, PLAYER1, PLAYER2, PLAYER3, PLAYER4, DELETED_PLAYER }

const FOSSIL_NUM := 25
const ART_NUM := 15
const FISH_NUM := 40
const INSECT_NUM := 40
const TOTAL_NUM := FOSSIL_NUM + ART_NUM + FISH_NUM + INSECT_NUM
## Donatable art excludes Redd forgeries ART02/ART03.
const DONATABLE_ART_NUM := ART_NUM - 2
const DONATABLE_TOTAL := FOSSIL_NUM + DONATABLE_ART_NUM + FISH_NUM + INSECT_NUM

## `FTR_SUM_ART02` / `ART03` — Redd forgeries Blathers always rejects.
const FORGERY_ART_INDICES: Array[int] = [1, 2]

var _fossil: PackedByteArray = PackedByteArray()
var _art: PackedByteArray = PackedByteArray()
var _fish: PackedByteArray = PackedByteArray()
var _insect: PackedByteArray = PackedByteArray()


func _init() -> void:
	clear()


func clear() -> void:
	_fossil = _empty_bits(FOSSIL_NUM)
	_art = _empty_bits(ART_NUM)
	_fish = _empty_bits(FISH_NUM)
	_insect = _empty_bits(INSECT_NUM)


static func _empty_bits(count: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize((count + 1) >> 1)
	out.fill(0)
	return out


static func is_donated(donator: int) -> bool:
	return donator >= int(Donator.PLAYER1) and donator <= int(Donator.DELETED_PLAYER)


static func donator_exists(donator: int) -> bool:
	return donator >= int(Donator.PLAYER1) and donator <= int(Donator.PLAYER4)


func fossil_info(index: int) -> int:
	return _get_nibble(_fossil, index, FOSSIL_NUM)


func art_info(index: int) -> int:
	return _get_nibble(_art, index, ART_NUM)


func fish_info(index: int) -> int:
	return _get_nibble(_fish, index, FISH_NUM)


func insect_info(index: int) -> int:
	return _get_nibble(_insect, index, INSECT_NUM)


func info(category: int, index: int) -> int:
	match category:
		MuseumDisplay.Category.FOSSIL:
			return fossil_info(index)
		MuseumDisplay.Category.ART:
			return art_info(index)
		MuseumDisplay.Category.INSECT:
			return insect_info(index)
		MuseumDisplay.Category.FISH:
			return fish_info(index)
	return int(Donator.NONE)


func set_fossil(index: int, donator: int = int(Donator.PLAYER1)) -> bool:
	return _set_nibble(_fossil, index, FOSSIL_NUM, donator)


func set_art(index: int, donator: int = int(Donator.PLAYER1)) -> bool:
	return _set_nibble(_art, index, ART_NUM, donator)


func set_fish(index: int, donator: int = int(Donator.PLAYER1)) -> bool:
	return _set_nibble(_fish, index, FISH_NUM, donator)


func set_insect(index: int, donator: int = int(Donator.PLAYER1)) -> bool:
	return _set_nibble(_insect, index, INSECT_NUM, donator)


func count_fossils() -> int:
	return _count(_fossil, FOSSIL_NUM)


func count_art() -> int:
	return _count(_art, ART_NUM)


func count_fish() -> int:
	return _count(_fish, FISH_NUM)


func count_insects() -> int:
	return _count(_insect, INSECT_NUM)


func count_all() -> int:
	return count_fossils() + count_art() + count_fish() + count_insects()


func is_complete() -> bool:
	return count_all() >= DONATABLE_TOTAL


## Fill every display slot (`mMmd_DONATOR_PLAYER1`). Used by the completed-museum test scene.
func fill_complete(donator: int = int(Donator.PLAYER1)) -> void:
	for i: int in FOSSIL_NUM:
		set_fossil(i, donator)
	for i: int in ART_NUM:
		## Forgeries stay empty — they are never legitimately on display.
		if i in FORGERY_ART_INDICES:
			continue
		set_art(i, donator)
	for i: int in FISH_NUM:
		set_fish(i, donator)
	for i: int in INSECT_NUM:
		set_insect(i, donator)


## `mMmd_GetDisplayInfo`.
func display_info_for_item(item: ItemData) -> DisplayInfo:
	var mapped: Dictionary = MuseumDisplay.map_item(item)
	if mapped.is_empty():
		return DisplayInfo.CANNOT_DONATE
	var category: int = int(mapped.get("category", MuseumDisplay.Category.FOSSIL))
	var index: int = int(mapped.get("index", -1))
	if category == MuseumDisplay.Category.ART and index in FORGERY_ART_INDICES:
		return DisplayInfo.CANNOT_DONATE
	if is_donated(info(category, index)):
		return DisplayInfo.ALREADY_DONATED
	return DisplayInfo.CAN_DONATE


## `mMmd_RequestMuseumDisplay`. Writes the nibble after Blathers' putaway ends.
func request_display(item: ItemData, player_no: int = 0) -> bool:
	if item == null:
		return false
	if display_info_for_item(item) != DisplayInfo.CAN_DONATE:
		return false
	var mapped: Dictionary = MuseumDisplay.map_item(item)
	var category: int = int(mapped.get("category", MuseumDisplay.Category.FOSSIL))
	var index: int = int(mapped.get("index", -1))
	var donator: int = clampi(player_no, 0, 3) + 1
	match category:
		MuseumDisplay.Category.FOSSIL:
			return set_fossil(index, donator)
		MuseumDisplay.Category.ART:
			return set_art(index, donator)
		MuseumDisplay.Category.INSECT:
			return set_insect(index, donator)
		MuseumDisplay.Category.FISH:
			return set_fish(index, donator)
	return false


## `mMmd_DeletePresentedByPlayer` — remap a deleted player's slots to DELETED_PLAYER.
func delete_presented_by_player(player_no: int) -> void:
	if player_no < 0 or player_no > 3:
		return
	var search: int = player_no + 1
	_remap_player(_fossil, FOSSIL_NUM, search)
	_remap_player(_art, ART_NUM, search)
	_remap_player(_fish, FISH_NUM, search)
	_remap_player(_insect, INSECT_NUM, search)


func has_fish_id(fish_id: StringName) -> bool:
	var index: int = MuseumDisplay.fish_index(fish_id)
	return index >= 0 and is_donated(fish_info(index))


func has_insect_type(type_index: int) -> bool:
	return type_index >= 0 and type_index < INSECT_NUM and is_donated(insect_info(type_index))


func to_save() -> Dictionary:
	return {
		"fossil": Array(_fossil),
		"art": Array(_art),
		"fish": Array(_fish),
		"insect": Array(_insect),
	}


func apply_snapshot(data: Variant) -> void:
	clear()
	if typeof(data) != TYPE_DICTIONARY:
		return
	var row: Dictionary = data
	_load_bits(_fossil, row.get("fossil", []), FOSSIL_NUM)
	_load_bits(_art, row.get("art", []), ART_NUM)
	_load_bits(_fish, row.get("fish", []), FISH_NUM)
	_load_bits(_insect, row.get("insect", []), INSECT_NUM)


func _count(bits: PackedByteArray, count: int) -> int:
	var n: int = 0
	for i: int in count:
		if is_donated(_get_nibble(bits, i, count)):
			n += 1
	return n


func _remap_player(bits: PackedByteArray, count: int, search: int) -> void:
	for i: int in count:
		if _get_nibble(bits, i, count) == search:
			_set_nibble(bits, i, count, int(Donator.DELETED_PLAYER))


func _load_bits(bits: PackedByteArray, raw: Variant, count: int) -> void:
	if typeof(raw) != TYPE_ARRAY:
		return
	var arr: Array = raw
	for i: int in mini(arr.size(), bits.size()):
		bits[i] = clampi(int(arr[i]), 0, 255)
	## Ignore trailing bytes past the packed size for this category.
	var _unused: int = count


func _get_nibble(bits: PackedByteArray, index: int, count: int) -> int:
	if index < 0 or index >= count:
		return int(Donator.NONE)
	var byte_i: int = index >> 1
	if byte_i < 0 or byte_i >= bits.size():
		return int(Donator.NONE)
	var shift: int = (index & 1) << 2
	return (int(bits[byte_i]) >> shift) & 0x0F


func _set_nibble(bits: PackedByteArray, index: int, count: int, value: int) -> bool:
	if index < 0 or index >= count:
		return false
	var byte_i: int = index >> 1
	if byte_i < 0 or byte_i >= bits.size():
		return false
	var shift: int = (index & 1) << 2
	var raw: int = int(bits[byte_i])
	raw &= ~(0x0F << shift)
	raw |= (value & 0x0F) << shift
	bits[byte_i] = raw
	return true