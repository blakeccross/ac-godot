class_name ShopPresenter
extends RefCounted

## Stocks a Nook shop (`shop0`..`shop3_2`) with the day's goods as shelf props
## (`ShopBook.goods`). Tom Nook at his stand (or Timmy and Tommy upstairs) and the wall
## clock are authored in each shop's `.tscn` (`shop0N_actable`, `HOUSE_CLOCK`); the
## Cranny also gets solid hulls for its counter. Able Sisters stocks nothing and gets
## only the shelf pass.
##
## Stock nodes join the `"shop_set"` group so `interior.gd.refresh_shop_set` can
## rebuild them after a purchase without touching Nook or the clock.

const STOCK_SCENE := preload("res://features/shops/nook/shop_stock.tscn")


func present(root: Node3D, interior: IndoorSession) -> void:
	if root == null or interior == null or interior.room == null or Game == null:
		return
	var room: Room = interior.room
	var shop_id: StringName = Game.shops.shop_id_for_room(room)
	if shop_id == &"":
		return
	Game.shops.ensure_today(shop_id)
	if room.kind == Room.Kind.SHOP and room.id == &"shop0":
		InteriorUnitCollision.add_hulls(
			root, interior.grid, "NookFurnitureCol", ShopDisplay.cranny_blocked_units()
		)
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
			var stock: Node3D = _add_stock(root, i, shop_id, listed[i], _slot_pos(interior, row))
			var half_gx: float = float(row.get("half_gx", 0.0))
			if half_gx > 0.0 and stock != null:
				stock.call("set_footprint_gx", half_gx)


static func _slot_pos(interior: IndoorSession, slot: Dictionary) -> Vector3:
	var pos: Vector3 = interior.grid.cell_to_world(slot["cell"] as Vector2i)
	pos.y = float(slot["y_gx"]) * FieldCatalog.GX_TO_METERS
	return pos


func _add_stock(
	root: Node3D, i: int, shop_id: StringName, item_id: StringName, pos: Vector3, prize: bool = false
) -> Node3D:
	var node: Node3D = STOCK_SCENE.instantiate() as Node3D
	node.name = "ShopStock_%d" % i
	node.set("shop_id", shop_id)
	node.set("item_id", item_id)
	node.set("lottery_prize", prize)
	node.set("occupant_id", StringName("shop_stock_%d" % i))
	node.position = pos
	root.add_child(node)
	return node
