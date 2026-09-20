class_name HouseUpgrade
extends RefCounted

## House expansion rules (`m_home.c` `mHm_CheckRehouseOrder` / `mHm_SetBasement` and the
## Nook side in `ac_npc_shop_common.c`). An order only *records* the next size and today's
## date; the build lands the next time the game starts on a different day, and Nook then
## collects the matching loan the first time you talk to him after it.

## `aNSC_LOAN_*`.
const LOAN_MEDIUM := 148000
const LOAN_LARGE := 398000
const LOAN_UPPER := 798000
const LOAN_BASEMENT := 49800
const LOAN_STATUE := 0

## What Nook says after a build lands (`aNSC_MSG_*_BUILT`).
const BUILT_MEDIUM := &"medium_built"
const BUILT_LARGE := &"large_built"
const BUILT_UPPER := &"upper_built"
const BUILT_BASEMENT := &"basement_built"
const BUILT_STATUE := &"statue_built"

## What Nook offers when the loan is clear (`aNSC_set_talk_info_start_wait1` /
## `aNSC_WAIT_TYPE_DONE_REHOUSE`).
const OFFER_NONE := &""
const OFFER_MEDIUM := &"rehouse_medium"
const OFFER_BASEMENT_OR_SKIP := &"rehouse_2_offer"
const OFFER_BASEMENT_PAID := &"basement_paid"
const OFFER_BASEMENT := &"rehouse_basement"
const OFFER_LARGE := &"rehouse_large"
const OFFER_UPPER := &"rehouse_upper"
const OFFER_STATUE := &"rehouse_statue"

## Follow-up after the offer line (`aNSC_ACTION_*`).
const ACTION_ORDER_ROOF := &"check_roof_col_order"
const ACTION_ASK_BASEMENT := &"check_col_chg_or_make_basement"
const ACTION_AUTO_BASEMENT := &"auto_basement"


static func loan_for_tier(tier: int) -> int:
	match tier:
		House.SizeTier.MEDIUM:
			return LOAN_MEDIUM
		House.SizeTier.LARGE:
			return LOAN_LARGE
		House.SizeTier.UPPER:
			return LOAN_UPPER
		_:
			return LOAN_STATUE


static func is_statue(house: House) -> bool:
	return house != null and house.next_size_tier == House.SizeTier.STATUE


static func stamp_today(house: House) -> void:
	if house == null:
		return
	house.order_year = Clock.year
	house.order_month = Clock.month
	house.order_day = Clock.day


## `CHECK_ORDER_DATE`: true when the order was placed on some other day than today.
static func order_is_stale(house: House) -> bool:
	if house == null:
		return false
	return (
		house.order_day != Clock.day
		or house.order_month != Clock.month
		or house.order_year != Clock.year
	)


## `mHm_SetBasement`.
static func set_basement(house: House) -> bool:
	if house == null or house.has_basement:
		return false
	house.has_basement = true
	return true


## `mHm_CheckRehouseOrder` for one occupied house. True when anything changed.
static func check_rehouse_order(house: House) -> bool:
	if house == null:
		return false
	var changed := false
	if house.outlook_pal != house.next_outlook_pal:
		house.outlook_pal = house.next_outlook_pal
		changed = true
	if house.size_tier != house.next_size_tier and house.next_size_tier < House.SizeTier.STATUE:
		if order_is_stale(house):
			house.outlook_pal = house.ordered_outlook_pal
			house.next_outlook_pal = house.ordered_outlook_pal
			house.size_tier = house.next_size_tier
			house.renew = true
			changed = true
	elif house.basement_ordered:
		if order_is_stale(house):
			set_basement(house)
			house.renew = true
			changed = true
	elif house.statue_ordered:
		if order_is_stale(house) and house.next_size_tier != House.SizeTier.STATUE:
			house.next_size_tier = House.SizeTier.STATUE
			changed = true
	return changed


## Nook's "Which roof colour?" answer (`aNSC_check_roof_col_order`): bumps `next_size`,
## remembers the palette and stamps the day. `palette` is 0..11.
static func order_upgrade(house: House, palette: int) -> bool:
	if house == null or house.next_size_tier >= House.SizeTier.UPPER:
		return false
	if house.size_tier != house.next_size_tier or house.basement_ordered:
		return false
	house.next_size_tier = (int(house.next_size_tier) + 1) as House.SizeTier
	house.ordered_outlook_pal = clampi(palette, 0, House.OUTLOOK_PAL_COUNT - 1)
	stamp_today(house)
	return true


## `aNSC_set_make_basement_info`.
static func order_basement(house: House) -> bool:
	if house == null or house.has_basement or house.basement_ordered:
		return false
	if house.size_tier < House.SizeTier.MEDIUM or house.size_tier > House.SizeTier.LARGE:
		return false
	house.basement_ordered = true
	stamp_today(house)
	return true


## `aNSC_set_talk_info_start_wait` renew branch: hand over the next loan and say which
## build landed. Returns `{ "built": StringName, "loan": int }` or `{}` when nothing landed.
static func collect_built(house: House, inventory: Inventory) -> Dictionary:
	if house == null or not house.renew:
		return {}
	var built: StringName
	var next_loan: int
	house.basement_just_built = false
	if house.basement_ordered:
		house.basement_ordered = false
		next_loan = LOAN_BASEMENT
		house.basement_just_built = true
		built = BUILT_BASEMENT
	else:
		match house.size_tier:
			House.SizeTier.MEDIUM:
				built = BUILT_MEDIUM
			House.SizeTier.LARGE:
				built = BUILT_LARGE
			_:
				built = BUILT_UPPER
		next_loan = loan_for_tier(house.size_tier)
	if inventory != null:
		inventory.set_loan(next_loan)
	house.renew = false
	return {"built": built, "loan": next_loan}


## Statue ordering when the last loan is clear (`aNSC_set_talk_info_start_wait`). Returns the
## new global statue count, or −1 when the offer does not apply.
static func offer_statue(house: House, inventory: Inventory, statues_built: int) -> int:
	if house == null or inventory == null:
		return -1
	if (
		inventory.loan != 0
		or house.size_tier != House.SizeTier.UPPER
		or house.size_tier != house.next_size_tier
		or house.statue_ordered
	):
		return -1
	house.statue_ordered = true
	house.statue_rank = clampi(statues_built, 0, 3)
	stamp_today(house)
	return mini(statues_built + 1, 3)


## Which upgrade Nook opens with once the loan is settled
## (`aNSC_WAIT_TYPE_DONE_REHOUSE`). `{ "offer": <OFFER_*>, "action": <ACTION_*> }`, or `{}`.
static func offer_for(house: House, inventory: Inventory) -> Dictionary:
	if house == null or inventory == null:
		return {}
	if inventory.loan != 0 or house.renew:
		return {}
	if house.size_tier >= House.SizeTier.UPPER:
		return {}
	if house.size_tier != house.next_size_tier or house.basement_ordered:
		return {}
	match house.size_tier:
		House.SizeTier.SMALL:
			return {"offer": OFFER_MEDIUM, "action": ACTION_ORDER_ROOF}
		House.SizeTier.MEDIUM:
			if not house.has_basement:
				return {"offer": OFFER_BASEMENT_OR_SKIP, "action": ACTION_ASK_BASEMENT}
			return {"offer": OFFER_BASEMENT_PAID, "action": ACTION_ORDER_ROOF}
		House.SizeTier.LARGE:
			if house.basement_just_built:
				return {"offer": OFFER_UPPER, "action": ACTION_ORDER_ROOF}
			if not house.has_basement:
				## Nook orders the basement himself (`aNSC_set_make_basement_info`).
				return {"offer": OFFER_BASEMENT, "action": ACTION_AUTO_BASEMENT}
			return {"offer": OFFER_LARGE, "action": ACTION_ORDER_ROOF}
	return {}
