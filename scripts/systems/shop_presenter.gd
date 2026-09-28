class_name ShopPresenter
extends RefCounted

## Furnishes a Nook shop (`shop0`..`shop3_2`): Tom Nook at his stand, the wall
## clock, and the day's stock as shelf props (`shop0N_actable`, `HOUSE_CLOCK`,
## `ShopBook.goods`). Non-Nook counter shops fall back to a generic `ShopCounter`.
##
## Stock nodes join the `"shop_set"` group so `interior.gd.refresh_shop_set` can
## rebuild them after a purchase without touching Nook or the clock.

const COUNTER_SCENE := preload("res://scenes/world/shop_counter.tscn")
const STOCK_SCENE := preload("res://scenes/world/shop_stock.tscn")
const TOM_NOOK_SCENE := preload("res://scenes/world/interiors/tom_nook.tscn")


func present(root: Node3D, interior: IndoorSession) -> void:
	if root == null or interior == null or interior.room == null or Game == null:
		return
	var room: Room = interior.room
	var shop_id: StringName = Game.shops.shop_id_for_room(room)
	if shop_id == &"":
		return
	Game.shops.ensure_today(shop_id)
	if room.kind == Room.Kind.SHOP:
		_tom_nook(root, interior)
		_clock(root, interior)
	elif root.get_node_or_null("ShopCounter") == null:
		var counter: Node3D = COUNTER_SCENE.instantiate() as Node3D
		counter.name = "ShopCounter"
		counter.set("shop_id", shop_id)
		counter.position = interior.grid.cell_to_world(room.counter_cell())
		root.add_child(counter)
	_stock(root, interior, shop_id)


func _stock(root: Node3D, interior: IndoorSession, shop_id: StringName) -> void:
	## Every Nook floor lays the day's list out on its own FG reserve points
	## (`aSD_MakeGoodsFg`); sold slots stay empty until 06:00.
	var room: Room = interior.room
	var listed: Array[StringName] = Game.shops.lineup(shop_id)
	var sold: Array[int] = Game.shops.sold_slots(shop_id)
	## Raffle day: no goods, the prizes stand on the furniture points as 3, 1, 2
	## (`aSD_MakeLotteryGoodsFg`); a won prize ("") leaves its point empty.
	if shop_id == ShopBook.NOOK_ID and listed.is_empty() and Game.shops.is_lottery_day():
		var won: Array[StringName] = Game.shops.lottery_prizes()
		var points: Array[Dictionary] = []
		for slot: Dictionary in ShopDisplay.stock_slots(room.id):
			if slot["kind"] == &"furniture":
				points.append(slot)
		var order: Array[int] = [2, 0, 1]
		for n: int in mini(order.size(), points.size()):
			var i: int = order[n]
			if i < won.size() and won[i] != &"":
				_add_stock(root, i, shop_id, won[i], _slot_pos(interior, points[n]), true)
		return
	var rows: Array[Dictionary] = ShopDisplay.stock_placements_for_goods(
		listed, room.id, Game.shops.rare_item(shop_id), ShopGoods.is_halloween_stock(Clock.month, Clock.day)
	)
	for row: Dictionary in rows:
		var i: int = int(row["index"])
		if not sold.has(i):
			_add_stock(root, i, shop_id, listed[i], _slot_pos(interior, row))


static func _slot_pos(interior: IndoorSession, slot: Dictionary) -> Vector3:
	var pos: Vector3 = interior.grid.cell_to_world(slot["cell"] as Vector2i)
	pos.y = float(slot["y_gx"]) * FieldCatalog.GX_TO_METERS
	return pos


func _add_stock(
	root: Node3D, i: int, shop_id: StringName, item_id: StringName, pos: Vector3, prize: bool = false
) -> void:
	var node: Node3D = STOCK_SCENE.instantiate() as Node3D
	node.name = "ShopStock_%d" % i
	node.set("shop_id", shop_id)
	node.set("item_id", item_id)
	node.set("lottery_prize", prize)
	node.set("occupant_id", StringName("shop_stock_%d" % i))
	node.position = pos
	root.add_child(node)


func _tom_nook(root: Node3D, interior: IndoorSession) -> void:
	## `shop0N_actable` stand by upgrade level.
	if interior.grid == null:
		return
	var level: int = 0
	if interior.room != null:
		level = ShopDisplay.nook_level_for_room(interior.room.id)
	elif Game != null and Game.shops != null:
		level = Game.shops.nook_level()
	var stand: Vector3 = ShopDisplay.nook_stand_gx(level)
	var pos: Vector3 = ShopDisplay.gx_to_world(interior.grid, stand)
	var yaw: float = WorldGrid.yaw_for_facing(ShopDisplay.NOOK_FACING)
	var existing: Node3D = root.get_node_or_null("TomNook") as Node3D
	if existing != null:
		existing.position = pos
		existing.rotation.y = yaw
		return
	var nook: Node3D = TOM_NOOK_SCENE.instantiate() as Node3D
	nook.name = "TomNook"
	nook.position = pos
	nook.rotation.y = yaw
	root.add_child(nook)


func _clock(root: Node3D, interior: IndoorSession) -> void:
	## `HOUSE_CLOCK` / `aHC_position_data` for Nook shop scenes.
	if interior.grid == null or Game == null:
		return
	if root.get_node_or_null("NookClock") != null:
		return
	var visual: StringName = ShopDisplay.nook_clock_visual(Game.shops.nook_level())
	if FieldCatalog.mesh_paths(visual).is_empty():
		return
	var host := Node3D.new()
	host.name = "NookClock"
	host.position = ShopDisplay.gx_to_world(
		interior.grid, Vector3(ShopDisplay.CLOCK_GX.x, 0.0, ShopDisplay.CLOCK_GX.z)
	)
	root.add_child(host)
	var pivot: Node3D = GeneratedVisual.attach(host, visual)
	if pivot != null:
		VisualFit.align_actor_to_height_gx(pivot, ShopDisplay.CLOCK_GX.y)
