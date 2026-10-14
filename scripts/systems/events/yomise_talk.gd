class_name YomiseTalk
extends BankTalk

## Redd's night stall at the fireworks (`ac_ev_yomise`, messages 0x1757–0x1767). One kind of
## summer goods a night — fans, pinwheels or balloons — eight colours, one of each
## (`setUp_yomise_goods`), sold at a fixed price. The menu shows three at a time plus a way
## out (`aEYMS_set_choise_data`); buying pays, hands it over and asks about another.

const MSG_SOLD_OUT := 0x1757
## `msg_no[kind]`: the pitch for fans, pinwheels, balloons.
const MSG_PITCH: Array[int] = [0x1758, 0x1759, 0x175A]
const MSG_FULL := 0x175D
const MSG_BROKE := 0x175E
const MSG_LAST_FEW := 0x1761
const MSG_PICK := 0x1762
const MSG_NOTHING := 0x1763
const MSG_BOUGHT := 0x1764
const MSG_EMPTIED := 0x1765
const MSG_ANOTHER := 0x1766
const MSG_MORE := 0x1767
const PRICE: Array[int] = [780, 680, 480]
const GOODS_COUNT := 8
const PAGE := 3
## `sell_table[kind] + j`.
const GOODS: Array = [
	[&"bluebell_fan", &"plum_fan", &"bamboo_fan", &"cloud_fan", &"maple_fan", &"fan_fan", &"flower_fan", &"leaf_fan"],
	[&"yellow_pinwheel", &"red_pinwheel", &"tiger_pinwheel", &"green_pinwheel", &"pink_pinwheel",
		&"striped_pinwheel", &"flower_pinwheel", &"fancy_pinwheel"],
	[&"red_balloon", &"yellow_balloon", &"blue_balloon", &"green_balloon", &"purple_balloon",
		&"bunny_p_balloon", &"bunny_b_balloon", &"bunny_o_balloon"],
]
const NOT_BUYING := "I'm not buying!"
const NOT_THESE := "I don't want it!"

## `aEv_yomise_save_c`: `{kind, goods: [id or ""]}` for tonight.
var area: Dictionary = {}
var inventory: Inventory
var item: StringName = &""
var _start: int = 0
var _next_start: int = 0
var _shown: Array[int] = []


func _init(p_area: Dictionary, p_inventory: Inventory = null, rng: RandomNumberGenerator = null) -> void:
	area = p_area
	inventory = p_inventory
	if not area.has("goods"):
		var kind: int = rng.randi_range(0, 2) if rng != null else 0
		area["kind"] = kind
		var goods: Array = []
		for id: Variant in GOODS[kind]:
			goods.append(String(id))
		area["goods"] = goods


func kind() -> int:
	return int(area.get("kind", 0))


func goods() -> Array:
	return area.get("goods", [])


## `aYMS_check_goods_cnt`.
func left_from(start: int) -> int:
	var n: int = 0
	var g: Array = goods()
	for i: int in range(start, g.size()):
		if str(g[i]) != "":
			n += 1
	return n


func start_msg() -> int:
	return MSG_SOLD_OUT if left_from(0) == 0 else MSG_PITCH[kind()]


func prepare() -> void:
	set_free(0, number(PRICE[kind()]))


## "Buy one?" (the pitch) or "anything else?" → the goods menu.
func pick_step(msg_no: int, index: int) -> Dictionary:
	if index != 0:
		return {}
	if msg_no in MSG_PITCH:
		_start = 0
		return _menu()
	if msg_no == MSG_MORE:
		return _menu()
	return {}


## `aEYMS_to_talk_buy`.
func _menu() -> Dictionary:
	var labels: Array = []
	_shown.clear()
	var g: Array = goods()
	var j: int = _start
	while _shown.size() < PAGE and j < GOODS_COUNT:
		if str(g[j]) != "":
			_shown.append(j)
			labels.append(_name(StringName(str(g[j]))))
		j += 1
	_next_start = j
	labels.append(NOT_BUYING if j == GOODS_COUNT else NOT_THESE)
	return msg(MSG_LAST_FEW if left_from(_start) < 4 else MSG_PICK, labels)


## `aEYMS_talk_fruit`.
func choose(index: int) -> Dictionary:
	if index < 0 or index >= _shown.size():
		if left_from(_start) < 4:
			return msg(MSG_NOTHING)
		_start = _next_start
		return msg(MSG_MORE)
	var idx: int = _shown[index]
	var id := StringName(str(goods()[idx]))
	var data: ItemData = ItemCatalog.get_item(id)
	var price: int = PRICE[kind()]
	if inventory == null or not inventory.has_space(1):
		return msg(MSG_FULL)
	if inventory.wallet < price:
		return msg(MSG_BROKE)
	inventory.set_wallet(inventory.wallet - price)
	if data != null:
		inventory.add(data, 1)
	item = id
	goods()[idx] = ""
	_start = 0
	return msg(MSG_BOUGHT)


## `aEYMS_talk_give`: the goods change hands after "that'll come to …".
func next_step() -> Dictionary:
	if current_msg == MSG_BOUGHT and item != &"":
		var then: int = MSG_EMPTIED if left_from(0) == 0 else MSG_ANOTHER
		var gift: StringName = item
		item = &""
		return {"anim": {"give": gift}, "msg": then}
	return {}


static func _name(id: StringName) -> String:
	var data: ItemData = ItemCatalog.get_item(id)
	return data.display_name.to_lower() if data != null else String(id)
