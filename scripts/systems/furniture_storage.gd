class_name FurnitureStorage
extends RefCounted

## Dressers, wardrobes and closets keep up to three items (`aFTR_KEEP_ITEM_COUNT`). The state
## decides which conversation opens (`aMR_SetFtrDemoMsg`): the owner may put things in and take
## them out; anyone else in a villager's house only hears what is inside.

const DIALOGUE_ID := &"furniture_storage"
const VAR_SCENE := "storage_scene"

## Player clip pairs per chest type (`Player_actor_request_main_open_furniture`: closet 0x2B,
## drawers 0x2C, wardrobe 0x2D → `KAGU_OPEN_D1 / H1 / K1`).
const OPEN_CLIPS: Dictionary = {
	FurnitureData.StorageType.DRAWERS: &"ply_1_kagu_open_h1",
	FurnitureData.StorageType.WARDROBE: &"ply_1_kagu_open_k1",
	FurnitureData.StorageType.CLOSET: &"ply_1_kagu_open_d1",
}
const CLOSE_CLIPS: Dictionary = {
	FurnitureData.StorageType.DRAWERS: &"ply_1_kagu_close_h1",
	FurnitureData.StorageType.WARDROBE: &"ply_1_kagu_close_k1",
	FurnitureData.StorageType.CLOSET: &"ply_1_kagu_close_d1",
}


static func count(entry: FurniturePlacement) -> int:
	var n: int = 0
	if entry == null:
		return 0
	for id: String in entry.stored:
		if id != "":
			n += 1
	return n


## `aMR_TidyItemInFurniture`: close the gaps so slot 0 is always filled first.
static func tidy(entry: FurniturePlacement) -> void:
	if entry == null:
		return
	var kept := PackedStringArray()
	for id: String in entry.stored:
		if id != "":
			kept.append(id)
	entry.stored = kept


static func scene_for(entry: FurniturePlacement, is_owner: bool) -> StringName:
	tidy(entry)
	var n: int = mini(count(entry), FurnitureData.KEEP_SLOTS)
	var names: Array[StringName] = [&"empty", &"one", &"two", &"three"]
	var scene: StringName = names[n]
	return scene if is_owner else StringName("other_%s" % String(scene))


## `mMsg_Set_item_str_art`: the item names the message reads out.
static func fill_context(ctx: DialogueContext, entry: FurniturePlacement) -> void:
	if ctx == null or entry == null:
		return
	tidy(entry)
	ctx.item0 = _name_at(entry, 0)
	ctx.frees = PackedStringArray([_name_at(entry, 1), _name_at(entry, 2)])


static func _name_at(entry: FurniturePlacement, index: int) -> String:
	if index >= entry.stored.size():
		return ""
	var data: ItemData = ItemCatalog.get_item(StringName(entry.stored[index]))
	return data.display_name if data != null else entry.stored[index]


## `aMR_ItemPutInFurniture`.
static func put_in(entry: FurniturePlacement, item_id: StringName) -> bool:
	if entry == null or item_id == &"":
		return false
	tidy(entry)
	if entry.stored.size() >= FurnitureData.KEEP_SLOTS:
		return false
	entry.stored.append(String(item_id))
	return true


## Move slot `index` to the pockets. `&"ok"`, `&"full"` (pockets), or `&"none"` (nothing there).
static func take_out(entry: FurniturePlacement, index: int, inventory: Inventory) -> StringName:
	tidy(entry)
	if entry == null or index < 0 or index >= entry.stored.size():
		return &"none"
	var data: ItemData = ItemCatalog.get_item(StringName(entry.stored[index]))
	if data == null:
		entry.stored.remove_at(index)
		return &"none"
	if inventory == null or not inventory.has_space_for(data, 1):
		return &"full"
	inventory.add(data, 1)
	entry.stored.remove_at(index)
	return &"ok"
