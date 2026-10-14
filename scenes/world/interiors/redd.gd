extends EventNpc

## Crazy Redd inside his tent (`ac_ev_broker2`, `SP_NPC_EV_BROKER2`). He greets you as you
## come in (0x078B), keeps turning to face you, and names his price when you press A in
## front of one of the three pieces on the floor (`broker_design` at units (2,2), (4,2),
## (2,4)); `ReddTalk` runs the sale. The pieces are `ShopStock` props with shop id
## `broker_shop` that call `offer_item` here. Facing the way out, he sees you off and you
## leave (`aEBR2_message_ctrl` → `aEBR2_goodbye_wait`).

const SHOP_ID := &"broker_shop"
const STOCK_SCENE := preload("res://scenes/world/shop_stock.tscn")
## `item_ux` / `item_uz`.
const WARE_UNITS: Array[Vector2i] = [Vector2i(2, 2), Vector2i(4, 2), Vector2i(2, 4)]
## `aEBR2_search_player2` zone point (GX).
const STAND_GX := Vector3(60.0, 0.0, 100.0)
const MABEL := preload("res://scenes/world/interiors/mabel.gd")

var _greeted: bool = false
var _pending_item: StringName = &""
## `sell_flag`.
var _sold_visit: bool = false
var _bye_said: bool = false


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
			_sold_visit = true
			for n: Node in get_tree().get_nodes_in_group("shop_set"):
				if n.name.begins_with("ReddWare_") and StringName(str(n.get("item_id"))) == _pending_item:
					n.queue_free()
					break
	_pending_item = &""
	if t != null and t.kind == ReddTalk.Kind.GOODBYE:
		_leave()


## `aEBR2_message_ctrl`: the player at the exit strip, facing it (`EXIT_DOOR1`).
func _check_goodbye() -> bool:
	if _bye_said or talking or Game == null or Game.block_auto_enter_doors:
		return false
	var ui := DialogueOverlay.find(get_tree())
	if ui != null and ui.is_open():
		return false
	var player := Player.find(get_tree())
	var session: IndoorSession = Game.interior_session
	if player == null or player.is_busy() or session == null or session.grid == null or session.room == null:
		return false
	if not MABEL.facing_exit(session, player.global_position, player.facing_yaw()):
		return false
	var t := ReddTalk.new(ReddTalk.Kind.GOODBYE, _area(), Game.inventory, rng())
	t.sold_visit = _sold_visit
	_bye_said = true
	player.stop_for_door()
	## `mDemo_Set_camera(CAMERA2_PROCESS_NORMAL)`: no talk camera turn.
	if not begin_talk(null, t, false):
		_leave()
	return true


## `aEBR2_exit_wait`: out of the tent once the window has gone.
func _leave() -> void:
	var host: Node = get_tree().get_first_node_in_group("interior") if get_tree() != null else null
	if host != null and host.has_method("leave_through_exit"):
		host.call("leave_through_exit")
	elif Game != null:
		Game.exit_interior()


func think(delta: float) -> void:
	## `aEBR2_search_player`: keep facing the customer.
	if _check_goodbye():
		return
	var p: Node3D = player_node()
	if p == null:
		return
	var to: Vector3 = p.global_position - global_position
	if to.length_squared() > 0.01:
		turn_to(atan2(to.x, to.z), delta)
