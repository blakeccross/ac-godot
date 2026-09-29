class_name NookShopTalk
extends RefCounted

## Tom Nook's store conversations (`ac_npc_shop_common.c`, `ac_npc_shop_mastersp_talk.c_inc`):
## the counter menu (sell / catalog order / other → turnip price), the sell / order quote
## after a paper pick (Yes/No), the shelf offer ("That's X. N Bells. Want it?", with try-on
## for clothes), and the raffle-day drawing.
## Hosts fill the context, forward `{op:"nook_shop"}` events here and act on the returned
## follow-up (open the sell / order paper after the talk closes).

const MENU_ID := &"nook_shop_menu"
const OFFER_ID := &"nook_shop_offer"
const LOTTERY_ID := &"nook_lottery"
const DEAL_ID := &"nook_shop_deal"
## One-line talks: bank id first, authored fallback (`aNSC_MSG_START_CALL_NORMAL`,
## `aNSC_MSG_SAY_GOODBYE`, raffle-day `0x10E0` shelf / `0x10DF` prizes gone).
const WELCOME_BANK := &"msg_4241"
const WELCOME_ID := &"nook_greeting"
const GOODBYE_BANK := &"msg_4254"
const GOODBYE_ID := &"nook_shop_goodbye"
const LOTTERY_SHELF_BANK := &"msg_4320"
const LOTTERY_SHELF_ID := &"nook_lottery_shelf"
const LOTTERY_EMPTY_BANK := &"msg_4319"
const LOTTERY_EMPTY_ID := &"nook_lottery_empty"
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
## Tool / signboard thanks after a shelf buy (`aNSC_MSG_SELL_NET` … `SELL_SIGN`).
const VAR_TOOL := "shop_offer_tool"
## Paper pick being quoted: sell / sell_many / junk / sunday / order / unorderable.
const VAR_DEAL := "shop_deal"
const VAR_DEAL_ITEM := "shop_deal_item"
const VAR_DEAL_COUNT := "shop_deal_count"
const VAR_DEAL_RESULT := "shop_deal_result"

## Shelf items with their own purchase line (`aNSC_sell_answer0`).
const TOOL_LINES: Dictionary = {
	&"net": "net",
	&"axe": "axe",
	&"shovel": "shovel",
	&"fishing_rod": "rod",
	&"signboard": "sign",
}


## Bank line when converted, else the authored stand-in.
static func line(bank_id: StringName, fallback_id: StringName) -> DialogueData:
	var data: DialogueData = DialogueCatalog.conversation(bank_id)
	return data if data != null else DialogueCatalog.conversation(fallback_id)


## Entry greeting (`aNSC_start_wait`) as `{data, house}`: house business first (built /
## statue, or the upgrade + roof offer once the loan is paid, `..._start_wait1`), else the
## plain welcome. `{}` on raffle day: `ac_npc_shop_mastersp` has no greeting or house talk.
## `NookHouseTalk.plan` side effects (collecting the next loan) apply here.
static func entry_talk(house: House, inventory: Inventory, statues_built: int) -> Dictionary:
	if Game.shops.is_lottery_day():
		return {}
	var plan: Dictionary = NookHouseTalk.plan(house, inventory, statues_built)
	var house_data: DialogueData = (
		DialogueCatalog.conversation(NookHouseTalk.DIALOGUE_ID) if not plan.is_empty() else null
	)
	if house_data != null:
		return {"data": house_data, "house": plan}
	return {"data": line(WELCOME_BANK, WELCOME_ID), "house": {}}


## A on Nook: the counter menu (`aNSC_MSG_INTERACT_START`). Raffle-day Nook only runs the
## drawing (`0x10D1`) or says the prizes are gone (`0x10DF`).
static func counter_talk() -> DialogueData:
	if Game.shops.is_lottery_day():
		if lottery_empty():
			return line(LOTTERY_EMPTY_BANK, LOTTERY_EMPTY_ID)
		return DialogueCatalog.conversation(LOTTERY_ID)
	return DialogueCatalog.conversation(MENU_ID)


## A on a shelf good: the price offer, or on raffle day "prizes aren't for sale"
## (`player_buy` → `0x10E0`).
static func shelf_talk() -> DialogueData:
	if Game.shops.is_lottery_day():
		return line(LOTTERY_SHELF_BANK, LOTTERY_SHELF_ID)
	return DialogueCatalog.conversation(OFFER_ID)


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
	ctx.set_var(VAR_TOOL, str(TOOL_LINES.get(item_id, "")))
	ctx.set_var("shop_offer_item", String(item_id))


## Sell quote for a paper pick (`aNSC_msg_win_open_wait`: `SELL_OFFER` / `BUY_MANY_OFFER` /
## `JUNK_ACCEPT` / `KABU_ON_SUNDAY`). item0 = item, free0 = total, free1 = count.
static func fill_sell(ctx: DialogueContext, item_id: StringName, count: int) -> void:
	if ctx == null:
		return
	var data: ItemData = ItemCatalog.get_item(item_id)
	var quote: Dictionary = Game.shops.sell_quote(item_id, Game.inventory, count)
	var n: int = int(quote.get("count", 0))
	ctx.item0 = data.display_name if data != null else String(item_id)
	_set_free(ctx, 0, str(int(quote.get("total", 0))))
	_set_free(ctx, 1, str(n))
	var deal: String = "sell_many" if n > 1 else "sell"
	match int(quote.get("code", ShopBook.Sell.NOTHING)):
		ShopBook.Sell.JUNK:
			deal = "junk"
		ShopBook.Sell.SUNDAY_TURNIPS:
			deal = "sunday"
		ShopBook.Sell.NOTHING, ShopBook.Sell.QUEST, ShopBook.Sell.REFUSED:
			deal = "none"
	ctx.set_var(VAR_DEAL, deal)
	ctx.set_var(VAR_DEAL_ITEM, String(item_id))
	ctx.set_var(VAR_DEAL_COUNT, str(n))
	ctx.set_var(VAR_AGAIN, "yes")
	ctx.set_var(VAR_BALLOON, "no")
	ctx.set_var(VAR_SUNDAY, "yes" if Clock.weekday() == 0 else "no")


## Order quote for a catalog pick (`aNSC_msg_win_open_wait2`: `ORDER_OFFER` /
## `ORDER_UNAVAILABLE`). item0 = item, free0 = price.
static func fill_order(ctx: DialogueContext, item_id: StringName) -> void:
	if ctx == null:
		return
	var data: ItemData = ItemCatalog.get_item(item_id)
	ctx.item0 = data.display_name if data != null else String(item_id)
	_set_free(ctx, 0, str(ShopBook.buy_price(data)))
	ctx.set_var(VAR_DEAL, "order" if CatalogBook.is_orderable(data) else "unorderable")
	ctx.set_var(VAR_DEAL_ITEM, String(item_id))
	ctx.set_var(VAR_AGAIN, "yes")
	ctx.set_var(VAR_BALLOON, "no")
	ctx.set_var(VAR_SUNDAY, "yes" if Clock.weekday() == 0 else "no")


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


## Every raffle prize has been won (`check_null_lottery`).
static func lottery_empty() -> bool:
	for prize: StringName in Game.shops.lottery_prizes():
		if prize != &"":
			return false
	return true


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
		"sell_confirm":
			## `aNSC_buy_check` CHOICE0.
			var sell_id := StringName(str(ctx.get_var(VAR_DEAL_ITEM, "")) if ctx != null else "")
			var count: int = int(str(ctx.get_var(VAR_DEAL_COUNT, "1"))) if ctx != null else 1
			var sold: Dictionary = Game.shops.sell_result(ShopBook.NOOK_ID, sell_id, Game.inventory, count)
			var result: String = "fail"
			match int(sold.get("code", ShopBook.Sell.NOTHING)):
				ShopBook.Sell.OK:
					result = "ok"
				ShopBook.Sell.JUNK:
					result = "junk"
				ShopBook.Sell.OVERFLOW:
					result = "overflow"
			if ctx != null:
				ctx.set_var(VAR_DEAL_RESULT, result)
			out["sold"] = result == "ok" or result == "junk"
		"order_confirm":
			## `aNSC_order_check` CHOICE0: money checked first, then the order is placed.
			var order_id := StringName(str(ctx.get_var(VAR_DEAL_ITEM, "")) if ctx != null else "")
			var odata: ItemData = ItemCatalog.get_item(order_id)
			var state: String = "ok"
			if odata == null or not CatalogBook.is_orderable(odata):
				state = "fail"
			elif not Game.catalog.has_free_order():
				state = "full"
			elif not ShopBook.can_afford(Game.inventory, ShopBook.buy_price(odata)):
				state = "no_money"
			else:
				Game.shops.order(order_id, Game.inventory, Game.catalog)
			if ctx != null:
				ctx.set_var(VAR_DEAL_RESULT, state)
			out["ordered"] = state == "ok"
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
				var prizes_left: bool = not lottery_empty()
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
