extends EventNpc

## Crazy Redd inside his tent (`ac_ev_broker2`, `SP_NPC_EV_BROKER2`). He greets you as you
## come in (0x078B), keeps turning to face you, and names his price when you press A in
## front of one of the three pieces on the floor (`broker_design` at units (2,2), (4,2),
## (2,4)); `ReddTalk` runs the sale. The pieces are `ShopStock` props with shop id
## `broker_shop` that call `offer_item` here.

const SHOP_ID := &"broker_shop"
const STOCK_SCENE := preload("res://scenes/world/shop_stock.tscn")
## `item_ux` / `item_uz`.
const WARE_UNITS: Array[Vector2i] = [Vector2i(2, 2), Vector2i(4, 2), Vector2i(2, 4)]
## `aEBR2_search_player2` zone point (GX).
const STAND_GX := Vector3(60.0, 0.0, 100.0)

var _greeted: bool = false
var _pending_item: StringName = &""


func _init() -> void:
	species = &"fox"
	display_name = "Redd"


func setup() -> void:
	add_to_group("broker_redd")
	add_to_group("broker_set")
	var area: Dictionary = _area()
	## `aEBR2_say_hello_init`: remember they came in; the Redd outside stays hidden.
	area["entered"] = true
	area["hide_npc"] = true
	call_deferred("_place_wares")
	call_deferred("_say_hello")


func _area() -> Dictionary:
	return Game.events.area(&"broker_sale") if Game != null and Game.events != null else {}


func _place_wares() -> void:
	var interior: Node = get_tree().get_first_node_in_group("interior") if get_tree() != null else null
	var grid: WorldGrid = interior.get("grid") as WorldGrid if interior != null and "grid" in interior else null
	var items: Array[StringName] = ReddStock.items(_area())
	for i: int in mini(items.size(), WARE_UNITS.size()):
		if items[i] == &"":
			continue
		var node: Node3D = STOCK_SCENE.instantiate() as Node3D
		node.name = "ReddWare_%d" % i
		node.set("shop_id", SHOP_ID)
		node.set("item_id", items[i])
		node.set("occupant_id", StringName("redd_ware_%d" % i))
		node.position = grid.cell_to_world(WARE_UNITS[i]) if grid != null else global_position + Vector3(i * 2.0, 0, -2)
		get_parent().add_child(node)


func _say_hello() -> void:
	if _greeted:
		return
	_greeted = true
	begin_talk(player_node(), ReddTalk.new(ReddTalk.Kind.HELLO, _area(), Game.inventory if Game != null else null, rng()))


func make_talk() -> BankTalk:
	return ReddTalk.new(ReddTalk.Kind.CHAT, _area(), Game.inventory if Game != null else null, rng())


## Called by a `ShopStock` in the tent (`aEBR2_message_ctrl`, A in front of a piece).
func offer_item(item_id: StringName, ctx: InteractionContext) -> bool:
	if talking:
		return false
	var t := ReddTalk.new(ReddTalk.Kind.OFFER, _area(), Game.inventory if Game != null else null, rng())
	t.item_id = item_id
	t.explained = get_meta("explained", {})
	_pending_item = item_id
	return begin_talk(ctx.actor as Node3D if ctx != null else player_node(), t)


func talk_ended(script: BankTalk) -> void:
	var t := script as ReddTalk
	if t != null and t.kind == ReddTalk.Kind.OFFER:
		set_meta("explained", t.explained)
		if t.sold_now:
			for n: Node in get_tree().get_nodes_in_group("shop_set"):
				if n.name.begins_with("ReddWare_") and StringName(str(n.get("item_id"))) == _pending_item:
					n.queue_free()
					break
	_pending_item = &""


func think(delta: float) -> void:
	## `aEBR2_search_player`: keep facing the customer.
	var p: Node3D = player_node()
	if p == null:
		return
	var to: Vector3 = p.global_position - global_position
	if to.length_squared() > 0.01:
		turn_to(atan2(to.x, to.z), delta)
