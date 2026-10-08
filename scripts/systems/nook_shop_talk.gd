class_name NookShopTalk
extends RefCounted

## Tom Nook's store conversations (`ac_npc_shop_common.c`, `ac_npc_shop_mastersp_talk.c_inc`):
## the counter menu (sell / catalog order / other → turnip price), the shelf offer
## ("That's X. N Bells. Want it?", with try-on for clothes), and the raffle-day drawing.
## Hosts fill the context, forward `{op:"nook_shop"}` events here and act on the returned
## follow-up (open the pockets to sell / the catalog after the talk closes).

const MENU_ID := &"nook_shop_menu"
const OFFER_ID := &"nook_shop_offer"
const LOTTERY_ID := &"nook_lottery"
## After the pockets close in sell mode (`aNSC_buy_sum_check` / `aNSC_buy_check`).
const SELL_ID := &"nook_shop_sell"
const ORDER_ID := &"nook_shop_order"
## What came back from the catalog: offer / unavailable / cancel.
const VAR_ORDER_PICK := "shop_order_pick"
const VAR_ORDER_DONE := "shop_order_done"
const VAR_ORDER_ITEM := "shop_order_item"
const VAR_SELL := "shop_sell"
const VAR_SELL_DONE := "shop_sell_done"
const OP := "nook_shop"
## Secret codes (`aNSC_request_Q_answer_wait2`, `aNSC_pc_*`, `aNSC_pw_*`): what Nook says about
## a code told to him or one he makes.
const CODE_ID := &"nook_shop_code"
const VAR_CODE := "shop_code"
const VAR_CODE_RESULT := "shop_code_result"
## `Common_Get(unk_nook_present_count)`: three code presents a session.
const CODE_GIFTS_MAX := 3
## `hit_rate_magazine`: the chance a magazine code wins, by its hit rate.
const MAGAZINE_ODDS: Array[float] = [80.0, 60.0, 30.0, 0.0, 100.0]

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


## What the picked pocket slots add up to, per item: {item_id: count}.
static func sell_selection(slots: Array[int]) -> Dictionary:
	var out: Dictionary = {}
	for idx: int in slots:
		var slot: InventorySlot = Game.inventory.slot_at(idx)
		if slot == null or slot.is_empty():
			continue
		var id: StringName = slot.item.item_id
		out[id] = int(out.get(id, 0)) + maxi(slot.item.count, 1)
	return out


## `aNSC_buy_check_init`: free0 = the total, item0 = the item (one kind) or "these";
## `shop_sell` = ok / junk (worth nothing) / sunday (turnips) / refused.
static func fill_sell(ctx: DialogueContext, selection: Dictionary) -> void:
	if ctx == null:
		return
	var total: int = 0
	var state: String = "junk"
	for id: StringName in selection:
		var quote: Dictionary = Game.shops.sell_quote(id, Game.inventory, int(selection[id]))
		match int(quote["code"]):
			ShopBook.Sell.OK:
				state = "ok"
				total += int(quote["total"])
			ShopBook.Sell.SUNDAY_TURNIPS:
				if state == "junk":
					state = "sunday"
			ShopBook.Sell.QUEST, ShopBook.Sell.NOTHING:
				if state == "junk":
					state = "refused"
	_set_free(ctx, 0, str(total))
	if selection.size() == 1:
		var data: ItemData = ItemCatalog.get_item(selection.keys()[0] as StringName)
		ctx.item0 = data.display_name if data != null else ""
	else:
		ctx.item0 = "these"
	ctx.set_var(VAR_SELL, state)


## Handle one `{op:"nook_shop"}` event. Returns {notice, open} where `open` is
## &"sell" / &"order" when the pockets / catalog should open after the talk.
static func apply_event(event: Dictionary, ctx: DialogueContext) -> Dictionary:
	var out: Dictionary = {"notice": "", "open": &""}
	if str(event.get("op", "")) != OP or Game == null:
		return out
	match str(event.get("action", "")):
		"sell":
			out["open"] = &"sell"
		"order":
			## `aNSC_request_Q_answer_wait`: a full order sheet, else the catalog.
			var state: String = "ok" if Game.catalog.has_free_order() else "full"
			if ctx != null:
				ctx.set_var(VAR_ORDER, state)
			if state == "ok":
				out["open"] = &"order"
		"order_confirm":
			var item_id := StringName(str(ctx.get_var(VAR_ORDER_ITEM, "")) if ctx != null else "")
			var code: int = Game.shops.order_result(item_id, Game.inventory, Game.catalog)
			if ctx != null:
				ctx.set_var(VAR_ORDER_DONE, "ok" if code == ShopBook.Order.OK
					else ("no_money" if code == ShopBook.Order.NO_MONEY else "full"))
		"sell_confirm":
			var selection: Dictionary = sell_selection(Game.shop_sell_slots)
			var done: String = "ok"
			var paid: int = 0
			for id: StringName in selection:
				var res: Dictionary = Game.shops.sell_result(ShopBook.NOOK_ID, id, Game.inventory, int(selection[id]))
				if int(res.get("code", -1)) == ShopBook.Sell.OVERFLOW:
					done = "full"
				paid += int(res.get("paid", 0))
			Game.shop_sell_slots = []
			if ctx != null:
				ctx.set_var(VAR_SELL_DONE, done)
		"code_say":
			## Say code: a visitor collects at home, three a session, room in the pockets.
			var say: String = "ask"
			if Game.foreigner:
				say = "foreign"
			elif Game.nook_code_gifts >= CODE_GIFTS_MAX:
				say = "out"
			elif Game.inventory.empty_slot_count() <= 0:
				say = "full"
			if ctx != null:
				ctx.set_var(VAR_CODE, say)
			if say == "ask":
				out["open"] = &"code_say"
		"code_hear":
			## Hear code: only with something in the pockets that can be traded in.
			var hear: String = "ask" if Game.inventory.has_putin_candidates(&"code_gift") else "none"
			if ctx != null:
				ctx.set_var(VAR_CODE, hear)
			if hear == "ask":
				out["open"] = &"code_hear"
		"code_retry":
			out["open"] = &"code_say"
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


## `aNSC_pc_check_password`: what a code told to Nook comes to. `{result, item}` — result is
## `good` (the item is for this player), `magazine_miss`, `carde` (to be mailed to a villager),
## `bad` (someone else's) or `wrong` (not a code, or nothing the port has).
static func redeem(code: String, player: String, town: String, rng: RandomNumberGenerator) -> Dictionary:
	var f: Dictionary = SecretCode.decode(code)
	if f.is_empty() or SecretCode.tampered(f):
		return {"result": "wrong", "item": &""}
	var item: StringName = CodeItems.id_of(int(f["item"]))
	if item == &"":
		return {"result": "wrong", "item": &""}
	var mine: bool = SecretCode.for_player(f, player, town)
	var hit: int = int(f["hit_rate"])
	var result: String = "wrong"
	match int(f["type"]):
		SecretCode.Type.FAMICOM, SecretCode.Type.USER:
			if hit == 1:
				result = "good" if mine else "bad"
		SecretCode.Type.POPULAR:
			if hit == 1 and int(f["npc_code"]) >= 0:
				result = "good" if mine else "bad"
		SecretCode.Type.CARD_E:
			result = "carde"
		SecretCode.Type.MAGAZINE:
			if hit <= 4:
				result = "good" if rng.randf() * 100.0 < MAGAZINE_ODDS[hit] else "magazine_miss"
		SecretCode.Type.CARD_E_MINI:
			if hit == 1:
				result = "good"
	return {"result": result, "item": item}


## `aNSC_pw_*`: the code Nook makes so `player` in `town` can pick up `item_id` (type USER).
static func make_code(player: String, town: String, item_id: StringName) -> String:
	return SecretCode.make(
		SecretCode.Type.USER, 1, SecretCode.name_bytes(player), SecretCode.name_bytes(town), CodeItems.number_of(item_id)
	)


## `aNSC_msg_win_open_wait2` + `aNSC_order_check_init`: item1 = the pick, free3 = its
## price; `shop_order_pick` = offer / unavailable (not for sale) / cancel (nothing picked).
static func fill_order(ctx: DialogueContext, item_id: StringName) -> void:
	if ctx == null:
		return
	var data: ItemData = ItemCatalog.get_item(item_id)
	ctx.set_var(VAR_ORDER_ITEM, String(item_id))
	if data == null:
		ctx.set_var(VAR_ORDER_PICK, "cancel")
		return
	ctx.item0 = data.display_name
	_set_free(ctx, 0, str(ShopBook.buy_price(data)))
	ctx.set_var(VAR_ORDER_PICK, "offer" if CatalogBook.is_orderable(data) else "unavailable")


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
