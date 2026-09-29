class_name ReddTalk
extends BankTalk

## Crazy Redd (`ac_ev_broker`, outside the tent; `ac_ev_broker2`, inside).
##
## Outside: first time 0x0788, after having been in 0x0789, after buying 0x078A (naming the
## piece); then he turns and goes in.
## Inside: 0x078B as you come in. A in front of a piece: he names it and its price (first
## look 0x0793–0x0797, again 0x07A1); yes → 0x0798–0x079C then the purse / pockets:
## 0x07A0 short of Bells, 0x079F no room, 0x079E sold. No → 0x079D. Talking to him: sold out
## 0x07A2, else (half the time) about your purchase 0x078C, else 0x078D–0x078F.

enum Kind { OUTSIDE, HELLO, CHAT, OFFER }

const MSG_OUT_FIRST := 0x0788
const MSG_OUT_AGAIN := 0x0789
const MSG_OUT_BOUGHT := 0x078A
const MSG_HELLO := 0x078B
const MSG_ABOUT_BUY := 0x078C
const MSG_CHAT := 0x078D
const MSG_OTHER_BUYER := 0x0790
const MSG_OFFER := 0x0793
const MSG_YES := 0x0798
const MSG_NO := 0x079D
const MSG_SOLD := 0x079E
const MSG_FULL := 0x079F
const MSG_BROKE := 0x07A0
const MSG_OFFER_AGAIN := 0x07A1
const MSG_SOLD_OUT := 0x07A2

var kind: Kind = Kind.CHAT
var area: Dictionary = {}
var inventory: Inventory
var rng: RandomNumberGenerator
var item_id: StringName = &""
## Pieces already described this visit (`explain_flag`).
var explained: Dictionary = {}
var been_inside: bool = false
var sold_now: bool = false


func _init(p_kind: Kind, p_area: Dictionary, p_inventory: Inventory = null, p_rng: RandomNumberGenerator = null) -> void:
	kind = p_kind
	area = p_area
	inventory = p_inventory
	rng = p_rng if p_rng != null else RandomNumberGenerator.new()
	if p_rng == null:
		rng.randomize()


func prepare() -> void:
	var mine: StringName = ReddStock.bought(area)
	if mine != &"":
		context.set_item_str(2, _name(mine))
	if item_id != &"":
		context.set_item_str(0, _name(item_id))
		set_free(0, number(ReddStock.price(item_id)))
	## `aEBR2_set_msg_data_sub`: another buyer's piece (a single-player town has none).
	var sold: Array = area.get("sold", [])
	for s: Variant in sold:
		if StringName(str(s)) != mine:
			context.set_item_str(1, _name(StringName(str(s))))


func start_msg() -> int:
	match kind:
		Kind.OUTSIDE:
			if ReddStock.bought(area) != &"":
				return MSG_OUT_BOUGHT
			return MSG_OUT_AGAIN if been_inside else MSG_OUT_FIRST
		Kind.HELLO:
			return MSG_HELLO
		Kind.OFFER:
			if explained.has(item_id):
				return MSG_OFFER_AGAIN
			explained[item_id] = true
			return MSG_OFFER + rng.randi_range(0, 4)
	## `aEBR2_set_talk_info_message_ctrl`.
	var r: int = rng.randi_range(0, 1)
	if int(area.get("used", 0)) >= ReddStock.ITEM_NUM:
		return MSG_SOLD_OUT
	if ReddStock.bought(area) != &"" and r == 0:
		return MSG_ABOUT_BUY
	return MSG_CHAT + rng.randi_range(0, 2)


## `aEBR2_sell_check`.
func picked(msg_no: int, index: int) -> int:
	if msg_no == MSG_OFFER_AGAIN or (msg_no >= MSG_OFFER and msg_no < MSG_OFFER + 5):
		return MSG_YES + rng.randi_range(0, 4) if index == 0 else MSG_NO
	return -1


## `aEBR2_sell_after`: at the end of "before you change your mind…".
func next_step() -> Dictionary:
	if current_msg < MSG_YES or current_msg >= MSG_YES + 5:
		return {}
	var cost: int = ReddStock.price(item_id)
	if inventory == null or not ShopBook.can_afford(inventory, cost):
		return msg(MSG_BROKE)
	var data: ItemData = ItemCatalog.get_item(item_id)
	if data == null or not inventory.has_space(1):
		return msg(MSG_FULL)
	ShopBook.pay(inventory, cost)
	inventory.add(data, 1)
	ReddStock.sell(area, item_id)
	sold_now = true
	return msg(MSG_SOLD)


static func _name(id: StringName) -> String:
	var data: ItemData = ItemCatalog.get_item(id)
	## `mMsg_SET_ITEM_STR_ART`: with its article (the messages cut it where they need to).
	return PoliceTalk.with_article(data.display_name) if data != null else ""
