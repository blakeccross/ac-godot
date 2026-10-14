class_name WispTalk
extends BankTalk

## What the Wisp says (`ac_ev_ghost_talk.c_inc`). Five variants of each line he calls out
## (`aEGH_set_force_talk_info`): "Excuse me…" when the player first comes near (0x2ED3),
## "Thank you for noticing me!" and the request when they find him (0x2EE2), "That's not the
## right way" if they wander off before that (0x2ED8), and "It's 4 o'clock!" at the end of
## the night (0x2EDD). Spoken to once found (`aEGH_set_norm_talk_info`), it depends on the
## spirits in the pockets: none (0x2EE7), one to four (0x2EEB + n), or all five (0x2EF0),
## which takes them (`aEGH_give_me_wait`) and offers a wish (`aEGH_select_wait`): the weeds
## (0x2EF1–0x2EF5 by how many there are), the roof (four pages of three colours,
## `aEGH_select_roof`) or an item the catalogue lacks (`aEGH_give_you_wait`). `{item1}` is
## whoever is going to yell at him.

enum Kind { EXCUSE_ME, FOUND, WRONG_WAY, TIME_UP, NORMAL }

const MSG_EXCUSE_ME := 0x2ED3
const MSG_WRONG_WAY := 0x2ED8
const MSG_TIME_UP := 0x2EDD
const MSG_FOUND := 0x2EE2
const MSG_NONE := 0x2EE7
const MSG_SOME := 0x2EEB
const MSG_ALL := 0x2EF0
const MSG_ITEM := 0x2EF9
const VARIANTS := 5
## Roof pages: their first colour (`roof_pal`), "Another color…" moving to the next.
const ROOF_PAGES: Dictionary = {12023: 0, 12028: 3, 12029: 6, 12030: 9, 12031: 0}
enum Wish { NONE, WEEDS, ROOF, ITEM }

var kind: int = Kind.NORMAL
var state: Dictionary = {}
var inventory: Inventory
var rng: RandomNumberGenerator
var wish: int = Wish.NONE
var item: StringName = &""
var roof: int = -1
var _taken: bool = false
var _given: bool = false


func _init(p_kind: int, p_state: Dictionary, p_inventory: Inventory, p_rng: RandomNumberGenerator) -> void:
	kind = p_kind
	state = p_state
	inventory = p_inventory
	rng = p_rng


func prepare() -> void:
	context.set_item_str(1, WispEvent.boss_name(state))


func start_msg() -> int:
	match kind:
		Kind.EXCUSE_ME:
			return MSG_EXCUSE_ME + rng.randi_range(0, VARIANTS - 1)
		Kind.WRONG_WAY:
			return MSG_WRONG_WAY + rng.randi_range(0, VARIANTS - 1)
		Kind.TIME_UP:
			return MSG_TIME_UP + rng.randi_range(0, VARIANTS - 1)
		Kind.FOUND:
			state["found"] = true
			state["active"] = true
			return MSG_FOUND + rng.randi_range(0, VARIANTS - 1)
	var n: int = WispEvent.spirit_count(inventory)
	if n == 0:
		return MSG_NONE + rng.randi_range(0, VARIANTS - 1)
	if n >= WispEvent.SPIRITS:
		## `event_save_common.ghost_day = 0`: the next visit is rolled afresh.
		if Game != null and Game.events != null:
			Game.events.ghost_day = 0
		return MSG_ALL
	return MSG_SOME + n


## `aEGH_give_me_wait` ("Please, show them to me!") and `aEGH_give_you_wait` (the gift).
func lock_continue() -> Dictionary:
	if current_msg == MSG_ALL and not _taken and order_value("npc0", 9) == 1:
		_taken = true
		if inventory != null:
			inventory.remove(WispEvent.SPIRIT_ID, WispEvent.spirit_count(inventory))
		return {"anim": {"take": WispEvent.SPIRIT_ID}}
	if current_msg == MSG_ITEM and not _given and item != &"" and order_value("npc0", 1) == 2:
		_given = true
		var data: ItemData = ItemCatalog.get_item(item)
		if data != null and inventory != null:
			inventory.add(data, 1)
		return {"anim": {"give": item}}
	return {}


func picked(msg_no: int, index: int) -> int:
	if msg_no == MSG_ALL:
		state["returned"] = true
		match index:
			0:
				wish = Wish.WEEDS
				return WispEvent.weeds_msg(WeedUse.count())
			1:
				wish = Wish.ROOF
			2:
				wish = Wish.ITEM
				var owned: Array = Game.catalog.owned_ids() if Game != null and Game.catalog != null else []
				item = WispEvent.wish_item(owned, rng)
				var data: ItemData = ItemCatalog.get_item(item)
				context.set_item_str(0, PoliceTalk.with_article(data.display_name) if data != null else "")
		return -1
	if ROOF_PAGES.has(msg_no) and index < 3:
		roof = int(ROOF_PAGES[msg_no]) + index
		_paint_roof(roof)
	return -1


## The new colour shows straight away, and stays unless a coat from Nook's is on order.
static func _paint_roof(palette: int) -> void:
	if Game == null or Game.interiors == null:
		return
	var house: House = Game.interiors.player_house()
	if house == null:
		return
	house.outlook_pal = clampi(palette, 0, House.OUTLOOK_PAL_COUNT - 1)
	if house.size_tier == house.next_size_tier:
		house.next_outlook_pal = house.outlook_pal


## `Save_Set(clear_grass, TRUE)`: the weeds go with the next growth.
func finish() -> void:
	if wish == Wish.WEEDS and Game != null:
		Game.clear_grass = true
