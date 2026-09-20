class_name NookHouseTalk
extends RefCounted

## What Tom Nook says about the player's house when they talk to him
## (`aNSC_start_wait` → `aNSC_set_talk_info_start_wait*`). `plan` runs the decomp's checks in
## order and applies the side effects that happen as he speaks (collecting the next loan,
## flagging the statue); `apply_event` records the answers the player gives.

const DIALOGUE_ID := &"nook_house"
const VAR_SCENE := "house_scene"
## Roof palettes are offered three at a time (`aNSC_check_roof_col_order` / `..._order2`).
const PALETTES_PER_PAGE := 3


## `{ "scene": StringName, "action": StringName }`, or `{}` when he has nothing to say about
## the house and the normal greeting plays.
static func plan(house: House, inventory: Inventory, statues_built: int) -> Dictionary:
	if house == null or inventory == null:
		return {}
	## A landed build: hand over the next loan and announce it.
	var built: Dictionary = HouseUpgrade.collect_built(house, inventory)
	if not built.is_empty():
		return {"scene": built["built"], "action": &""}
	## Statue finished the day after it was ordered.
	if house.statue_ordered and house.next_size_tier == House.SizeTier.STATUE:
		house.statue_ordered = false
		return {"scene": HouseUpgrade.BUILT_STATUE, "action": &""}
	## Last loan paid on the biggest house: offer the statue.
	var next_count: int = HouseUpgrade.offer_statue(house, inventory, statues_built)
	if next_count >= 0:
		return {
			"scene": HouseUpgrade.OFFER_STATUE,
			"action": &"",
			"statues_built": next_count,
		}
	var offer: Dictionary = HouseUpgrade.offer_for(house, inventory)
	if offer.is_empty():
		return {}
	return {"scene": offer["offer"], "action": offer["action"]}


## Side-effect-free check: does he have house business, so he greets first
## (`aNSC_start_wait` requests a SPEAK demo on entry)?
static func has_business(house: House, inventory: Inventory) -> bool:
	if house == null or inventory == null:
		return false
	if house.renew:
		return true
	if house.statue_ordered and house.next_size_tier == House.SizeTier.STATUE:
		return true
	if not HouseUpgrade.offer_for(house, inventory).is_empty():
		return true
	return (
		inventory.loan == 0
		and house.size_tier == House.SizeTier.UPPER
		and house.size_tier == house.next_size_tier
		and not house.statue_ordered
	)


## Fill the dialogue vars the `nook_house` graph branches on.
static func fill_context(ctx: DialogueContext, plan_result: Dictionary) -> void:
	if ctx == null:
		return
	ctx.set_var(VAR_SCENE, String(plan_result.get("scene", "")))


## Handle one dialogue event. Returns a short notice for the HUD ("" for none).
static func apply_event(event: Dictionary, house: House) -> String:
	if house == null:
		return ""
	match str(event.get("op", "")):
		"house_order_roof":
			var palette: int = int(event.get("palette", 0))
			if HouseUpgrade.order_upgrade(house, palette):
				return "Tom Nook will build your new house."
		"house_order_basement":
			if HouseUpgrade.order_basement(house):
				return "Tom Nook will dig your basement."
	return ""


## Palette ids on one page of the roof menu (page 0 is the default `check_roof_col_order`).
static func palettes_on_page(page: int) -> Array[int]:
	var out: Array[int] = []
	var first: int = clampi(page, 0, House.OUTLOOK_PAL_COUNT / PALETTES_PER_PAGE - 1) * PALETTES_PER_PAGE
	for i: int in PALETTES_PER_PAGE:
		out.append(first + i)
	return out
