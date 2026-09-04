class_name ShopUse
extends RefCounted

## Counter verbs. Hosts call `actions` / `apply`; they do not switch on shop type.


static func actions(host: Node, _ctx: InteractionContext) -> Array[Interaction]:
	var shop_id: StringName = _shop_id(host)
	if shop_id == &"":
		return []
	var out: Array[Interaction] = [Interaction.of(Interaction.BUY, "Buy", 12)]
	if Game != null and Game.shops != null and Game.shops.allows_sell(shop_id):
		out.append(Interaction.of(Interaction.SELL, "Sell", 11))
	return out


static func apply(action: Interaction, host: Node, _ctx: InteractionContext) -> bool:
	if action == null or host == null:
		return false
	var shop_id: StringName = _shop_id(host)
	if shop_id == &"":
		return false
	match action.id:
		Interaction.BUY, Interaction.SELL, Interaction.SHOP:
			var mode: StringName = Interaction.SELL if action.id == Interaction.SELL else Interaction.BUY
			return Game.open_shop(shop_id, mode)
		_:
			return false


static func _shop_id(host: Node) -> StringName:
	if host != null and "shop_id" in host:
		var from_host: StringName = host.get("shop_id") as StringName
		if from_host != &"":
			return from_host
	## Tom Nook / Able hosts live in a shop room without an exported shop_id.
	if Game == null:
		return &""
	var room: Room = Game.interiors.room(Game.current_room_id)
	return Game.shops.shop_id_for_room(room)
