class_name NookShopTalk
extends RefCounted

## Tom Nook's store conversations (`ac_npc_shop_common.c`, `ac_npc_shop_mastersp_talk.c_inc`):
## the counter menu (sell / catalog order / other → turnip price), the shelf offer
## ("That's X. N Bells. Want it?", with try-on for clothes), and the raffle-day drawing.
## Hosts fill the context, forward `{op:"nook_shop"}` events here and act on the returned
## follow-up (open the sell / order paper after the talk closes).

const MENU_ID := &"nook_shop_menu"
const OFFER_ID := &"nook_shop_offer"
const LOTTERY_ID := &"nook_lottery"
const OP := "nook_shop"

## Context vars the graphs branch on.
const VAR_AGAIN := "shop_again"
const VAR_BALLOON := "shop_balloon"
const VAR_ORDER := "shop_order"
const VAR_SUNDAY := "shop_sunday"
const VAR_KIND := "shop_offer_kind"
const VAR_BUY := "shop_buy"
const VAR_TICKET := "shop_ticket"
const VAR_LOTTERY := "shop_lottery"
const VAR_LOTTERY_AGAIN := "shop_lottery_again"


## Counter menu. free0 = store name, free1 = turnip price per turnip.
static func fill_menu(ctx: DialogueContext, already_talked: bool, balloon: StringName) -> void:
	if ctx == null:
		return
	var level: int = Game.shops.nook_level()
	_set_free(ctx, 0, ShopMail.store_name(level))
	_set_free(ctx, 1, str(Game.shops.kabu.price_today()))
	ctx.set_var(VAR_AGAIN, "yes" if already_talked else "no")
	ctx.set_var(VAR_BALLOON, "yes" if balloon != &"" else "no")
	ctx.set_var(VAR_SUNDAY, "yes" if Clock.weekday() == 0 else "no")
	if balloon != &"":
		var data: ItemData = ItemCatalog.get_item(balloon)
		ctx.item0 = data.display_name if data != null else String(balloon)


## Shelf offer. item0 = item, free0 = price.
static func fill_offer(ctx: DialogueContext, item_id: StringName) -> void:
	if ctx == null:
		return
	var data: ItemData = ItemCatalog.get_item(item_id)
	ctx.item0 = data.display_name if data != null else String(item_id)
	_set_free(ctx, 0, str(ShopBook.buy_price(data)))
	ctx.set_var(VAR_KIND, offer_kind(data))
	ctx.set_var("shop_offer_item", String(item_id))


static func offer_kind(data: ItemData) -> String:
	if data == null:
		return "item"
	if ShopBook.is_paint(data.id):
		return "paint"
	if data.category == ItemData.Category.CLOTH:
		return "cloth"
	return "item"


## Raffle. free0 = month name, free1 = tickets held.
static func fill_lottery(ctx: DialogueContext) -> void:
	if ctx == null:
		return
	_set_free(ctx, 0, ShopMail.MONTHS[clampi(Clock.month, 1, 12) - 1])
	_set_free(ctx, 1, str(Game.shops.ticket_count(Game.inventory)))


## Handle one `{op:"nook_shop"}` event. Returns {notice, open} where `open` is
## &"sell" / &"order" when a paper should open after the talk.
static func apply_event(event: Dictionary, ctx: DialogueContext) -> Dictionary:
	var out: Dictionary = {"notice": "", "open": &""}
	if str(event.get("op", "")) != OP or Game == null:
		return out
	match str(event.get("action", "")):
		"sell":
			out["open"] = &"sell"
		"order":
			var state: String = "ok"
			if not Game.catalog.has_free_order():
				state = "full"
			elif _orderable_count() == 0:
				state = "empty"
			if ctx != null:
				ctx.set_var(VAR_ORDER, state)
			if state == "ok":
				out["open"] = &"order"
		"try_on":
			var item_id := StringName(str(ctx.get_var("shop_offer_item", "")) if ctx != null else "")
			out["try_on"] = item_id
		"buy":
			var item_id := StringName(str(ctx.get_var("shop_offer_item", "")) if ctx != null else "")
			var res: Dictionary = Game.shops.buy_result(ShopBook.NOOK_ID, item_id, Game.inventory)
			if ctx != null:
				ctx.set_var(VAR_BUY, _buy_code_name(int(res.get("code", ShopBook.Buy.NOT_FOR_SALE))))
				ctx.set_var(VAR_TICKET, str(res.get("ticket", "")))
				if res.has("paint"):
					ctx.set_var(VAR_TICKET, "paint")
			out["bought"] = int(res.get("code", -1)) == ShopBook.Buy.OK
		"lottery":
			var draw: Dictionary = Game.shops.draw_lottery(Game.inventory)
			if ctx != null:
				var code: String = str(draw.get("code", "miss"))
				if code == "win":
					code = "win%d" % int(draw.get("place", 3))
					var data: ItemData = ItemCatalog.get_item(draw.get("item", &"") as StringName)
					ctx.item0 = data.display_name if data != null else ""
				ctx.set_var(VAR_LOTTERY, code)
				var left: int = Game.shops.ticket_count(Game.inventory)
				_set_free(ctx, 1, str(left))
				var prizes_left: bool = false
				for prize: StringName in Game.shops.lottery_prizes():
					if prize != &"":
						prizes_left = true
				ctx.set_var(
					VAR_LOTTERY_AGAIN,
					"yes" if left >= ShopBook.TICKETS_PER_DRAW and prizes_left else "no"
				)
	return out


static func _orderable_count() -> int:
	var n: int = 0
	for item_id: StringName in Game.catalog.owned_ids():
		if CatalogBook.is_orderable(ItemCatalog.get_item(item_id)):
			n += 1
	return n


static func _buy_code_name(code: int) -> String:
	match code:
		ShopBook.Buy.OK:
			return "ok"
		ShopBook.Buy.NO_MONEY:
			return "no_money"
		ShopBook.Buy.POCKETS_FULL:
			return "full"
		ShopBook.Buy.SOLD_OUT:
			return "sold_out"
		_:
			return "not_for_sale"


static func _set_free(ctx: DialogueContext, index: int, value: String) -> void:
	while ctx.frees.size() <= index:
		ctx.frees.append("")
	ctx.frees[index] = value
