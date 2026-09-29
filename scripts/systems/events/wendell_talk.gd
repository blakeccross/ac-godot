class_name WendellTalk
extends BankTalk

## Wendell, the hungry walrus artist (`ac_ev_artist_move.c_inc`). 0x02F5: "must eat!" —
## "it's all yours" opens the pockets (`mSM_IV_OPEN_GIVE`), "don't have any" 0x02F6.
## What he gets: nothing 0x02F6; a fish 0x02F9 and one of the event wallpapers in return
## (0x02FA); fruit 0x02F8; a tool is handed back 0x02FC; anything else he eats anyway
## 0x02F7. After his gift, 0x02FB (`aEART_check_present`: two players get a wallpaper,
## then everyone counts as served).

const MSG_HUNGRY := 0x02F5
const MSG_NOTHING := 0x02F6
const MSG_OTHER := 0x02F7
const MSG_FRUIT := 0x02F8
const MSG_FISH := 0x02F9
const MSG_THANKS := 0x02FA
const MSG_FULL := 0x02FB
const MSG_TOOL := 0x02FC
const ENTRY_SAVE_NUM := 2

var area: Dictionary = {}
var inventory: Inventory
var rng: RandomNumberGenerator
var present: StringName = &""


func _init(p_area: Dictionary, p_inventory: Inventory, p_rng: RandomNumberGenerator = null) -> void:
	area = p_area
	inventory = p_inventory
	rng = p_rng if p_rng != null else RandomNumberGenerator.new()
	if p_rng == null:
		rng.randomize()


## `aEART_check_present`.
func served() -> bool:
	return int(area.get("used", 0)) > ENTRY_SAVE_NUM or bool(area.get("gave_me", false))


func start_msg() -> int:
	return MSG_FULL if served() else MSG_HUNGRY


func pick_step(msg_no: int, index: int) -> Dictionary:
	if msg_no != MSG_HUNGRY:
		return {}
	if index == 0:
		return {"hand": {"pocket": -1, "mode": "take"}}
	return msg(MSG_NOTHING)


## `aEART_msg_win_open_wait`: what he was handed.
func hand_result(item: StringName, _pocket: int = -1) -> Dictionary:
	if item == &"":
		return msg(MSG_NOTHING)
	var data: ItemData = ItemCatalog.get_item(item)
	var category: int = data.category if data != null else ItemData.Category.OTHER
	if data is ToolData or category == ItemData.Category.TOOL:
		## Handed straight back (`aEART_refuse_demo_start_wait`).
		return {"anim": {"take": item}, "then": {"anim": {"give": item}, "msg": MSG_TOOL}}
	inventory.remove(item, 1)
	match category:
		ItemData.Category.FISH:
			return {"anim": {"take": item}, "msg": MSG_FISH}
		ItemData.Category.FRUIT:
			return {"anim": {"take": item}, "msg": MSG_FRUIT}
	return {"anim": {"take": item}, "msg": MSG_OTHER}


## After 0x02F9: `aEART_demo_start_wait_init` picks a wallpaper he hasn't given yet.
func next_step() -> Dictionary:
	if current_msg != MSG_FISH:
		return {}
	var given: Array = area.get("walls", [])
	present = FtrCatalog.pick_named("wall", "Event", rng, given)
	var used: int = int(area.get("used", 0))
	if used < ENTRY_SAVE_NUM:
		given.append(present)
		area["walls"] = given
	area["used"] = used + 1
	area["gave_me"] = true
	var data: ItemData = ItemCatalog.get_item(present)
	if data != null and inventory != null:
		inventory.add(data, 1)
	return {"anim": {"give": present}, "msg": MSG_THANKS}
