class_name DesignBook
extends RefCounted

## Original-design storage + Able Sisters shop state, owned by `Game`.
##
## Decomp: the player owns 8 designs (`Now_Private->my_org[8]`) with a display-order
## table (`my_org_no_table[8]`); the shop owns 8 shared designs
## (`Save_Get(needlework).original_design[8]`) — slots 0-3 clothing mannequins,
## 4-7 umbrella stands. Init in `src/game/m_needlework.c`
## (`mNW_InitOneMyOriginal` / `mNW_InitNeedleworkData`).
## Sable's "opening up" arc is driven by `Now_Private->nw_visitor` (day counter,
## capped at `aNNW_TALK_DAYS_MAX` = 10) in `ac_npc_needlework_talk.c_inc`.

const SLOT_COUNT := 8
const CLOTH_SLOTS := 4  ## shop slots 0-3
const SABLE_DAYS_MAX := 10  ## aNNW_TALK_DAYS_MAX

## mNW_InitMyOriginalPallet: pal_table {0,8,7,7,0,0,0,0}
const PLAYER_START_PALETTES: Array = [0, 8, 7, 7, 0, 0, 0, 0]
## mNW_InitNeedleworkPelatteNo: pal_table {7,1,10,3,6,0,6,7}
const SHOP_START_PALETTES: Array = [7, 1, 10, 3, 6, 0, 6, 7]

## ROM string table 0x6DF+i / 0x6E7+i (not yet extracted by the asset pipeline).
## TODO: replace with the real localized names once the string table is dumped.
const PLAYER_START_NAMES: Array = [
	"Sample 1", "Sample 2", "Sample 3", "Sample 4",
	"blank", "blank", "blank", "blank",
]
const SHOP_START_NAMES: Array = [
	"Bold Stripe", "Checkers", "Flower", "Argyle",
	"Rain", "Solid", "Polka Dot", "Herringbone",
]

signal changed
signal sable_day_advanced(days: int)

var player: Array[DesignPattern] = []
var player_order: PackedByteArray = PackedByteArray()
var shop: Array[DesignPattern] = []

## Sable friendship arc.
var sable_days: int = 0
var sable_last_date: String = ""
var sister_now: int = 0
var first_talk_done: bool = false
var listened_flag: bool = false

## Trend tracking (`aNNW_trend_check_cloth` / `_check_umbrella`). Index 0-3 = shop
## cloth slots, 4-7 = umbrella slots. `eligible` is set when the player puts one of
## their designs on a display; `count` grows each day a villager adopts it (capped
## at the town population) and resets to 0 when the design is removed
## (`aNNW_trend_delete_*`).
var trend_count: PackedInt32Array = PackedInt32Array()
var trend_eligible: PackedByteArray = PackedByteArray()
var trend_last_date: String = ""


func _init() -> void:
	clear()


func clear() -> void:
	player.clear()
	shop.clear()
	player_order = PackedByteArray()
	player_order.resize(SLOT_COUNT)
	for i in SLOT_COUNT:
		player_order[i] = i
		var pd: DesignPattern = _seed_player(i)
		player.append(pd)
		shop.append(_seed_shop(i))
	sable_days = 0
	sable_last_date = ""
	sister_now = 0
	first_talk_done = false
	listened_flag = false
	trend_count = PackedInt32Array()
	trend_count.resize(SLOT_COUNT)
	trend_eligible = PackedByteArray()
	trend_eligible.resize(SLOT_COUNT)
	trend_last_date = ""


## Placeholder motifs per starter slot until ARAM slots 27/28 are extracted.
const PLAYER_START_MOTIFS: Array = [
	DesignPattern.Motif.VSTRIPE, DesignPattern.Motif.CHECK,
	DesignPattern.Motif.FLOWER, DesignPattern.Motif.DIAMOND,
]
const SHOP_START_MOTIFS: Array = [
	DesignPattern.Motif.VSTRIPE, DesignPattern.Motif.CHECK, DesignPattern.Motif.FLOWER,
	DesignPattern.Motif.DIAMOND, DesignPattern.Motif.DIAGONAL, DesignPattern.Motif.HSTRIPE,
	DesignPattern.Motif.POLKA, DesignPattern.Motif.PLAID,
]


func _seed_player(i: int) -> DesignPattern:
	if i >= 4:
		return DesignPattern.blank()
	var d := _load_seed("player_%02d" % i, int(PLAYER_START_PALETTES[i]), int(PLAYER_START_MOTIFS[i]))
	d.name = str(PLAYER_START_NAMES[i])
	return d


func _seed_shop(i: int) -> DesignPattern:
	var d := _load_seed("shop_%02d" % i, int(SHOP_START_PALETTES[i]), int(SHOP_START_MOTIFS[i]))
	d.name = str(SHOP_START_NAMES[i])
	return d


## ARAM resource slots 27 (player) / 28 (shop) if the pipeline extracted them,
## else a generated placeholder motif.
func _load_seed(stem: String, palette_idx: int, motif: int) -> DesignPattern:
	var path := "res://assets/generated/needlework/%s.png" % stem
	if ResourceLoader.exists(path):
		var tex: Variant = load(path)
		var img: Image = (tex as Texture2D).get_image() if tex is Texture2D else null
		if img != null and img.get_width() == DesignPattern.WIDTH and img.get_height() == DesignPattern.HEIGHT:
			var d := DesignPattern.blank()
			d.palette = palette_idx
			d.flag_set = true
			d.pixels = _quantise(img, palette_idx)
			return d
	## fg/bg indices vary per motif so palettes with a dark tail still read well.
	var fg := 2 + (motif % 5)
	var bg := 9 if palette_idx not in [13, 14] else 4
	return DesignPattern.generate(motif, palette_idx, fg, bg)


func _quantise(img: Image, palette_idx: int) -> PackedByteArray:
	var pal := NeedleworkPalettes.colors(palette_idx)
	var out := PackedByteArray()
	out.resize(DesignPattern.WIDTH * DesignPattern.HEIGHT)
	for y in DesignPattern.HEIGHT:
		for x in DesignPattern.WIDTH:
			var c := img.get_pixel(x, y)
			var best := 0
			var best_d := 1e9
			for ci in NeedleworkPalettes.COLOR_COUNT:
				var pc := pal[ci]
				var dr := c.r - pc.r
				var dg := c.g - pc.g
				var db := c.b - pc.b
				var dist := dr * dr + dg * dg + db * db
				if dist < best_d:
					best_d = dist
					best = ci
			out[y * DesignPattern.WIDTH + x] = best
	return out


# --- lookups -----------------------------------------------------------------

## Design at display slot `slot` (0-7), following the order table
## (`mNW_get_image_no`).
func resolved(slot: int) -> DesignPattern:
	return player[player_order[slot & 7] & 7]


func resolved_index(slot: int) -> int:
	return player_order[slot & 7] & 7


# --- ops (mirror ac_needlework_indoor.c / ac_npc_needlework_talk.c_inc) ------

## Put a player design onto a shop mannequin / umbrella stand, one-way
## (`aNI_CopyClothData` / `TRADE_CLOSE2`). `shop_idx` 0-7.
func copy_player_to_shop(shop_idx: int, player_slot: int) -> void:
	shop[shop_idx & 7].copy_from(resolved(player_slot))
	trend_eligible[shop_idx & 7] = 1
	trend_count[shop_idx & 7] = 0
	changed.emit()


## True two-way swap between a shop slot and a player display slot
## (`aNI_ExchangeCloth` / `TRADE_CLOSE`).
func exchange(shop_idx: int, player_slot: int) -> void:
	var pi := resolved_index(player_slot)
	var tmp := shop[shop_idx & 7].duplicate_design()
	shop[shop_idx & 7].copy_from(player[pi])
	player[pi].copy_from(tmp)
	trend_eligible[shop_idx & 7] = 1
	trend_count[shop_idx & 7] = 0
	changed.emit()


## Design removed from a display (`aNNW_trend_delete_cloth` / `_delete_umbrella`).
func trend_delete(shop_idx: int) -> void:
	trend_eligible[shop_idx & 7] = 0
	trend_count[shop_idx & 7] = 0
	changed.emit()


## Once per day, roll whether a villager adopts each displayed player design.
func tick_trend(today: String, town_pop: int, rng: RandomNumberGenerator) -> void:
	if today == trend_last_date:
		return
	trend_last_date = today
	var cap: int = clampi(town_pop, 1, 8)
	for i in SLOT_COUNT:
		if trend_eligible[i] == 1 and trend_count[i] < cap and rng.randf() < 0.6:
			trend_count[i] += 1


## Highest-worn cloth (0-3) / umbrella (4-7) slot and its count (`aNNW_set_trend_*`).
func trend_top(is_umbrella: bool, rng: RandomNumberGenerator) -> Array:
	var base: int = 4 if is_umbrella else 0
	var best_idx: int = base + rng.randi_range(0, 3)
	var best: int = 0
	for i in 4:
		if trend_count[base + i] > best:
			best = trend_count[base + i]
			best_idx = base + i
	return [best_idx, best]


## Copy a shop design into a player slot (`TRADE_CLOSE3`).
func buy_shop_into_player(shop_idx: int, player_slot: int) -> void:
	player[resolved_index(player_slot)].copy_from(shop[shop_idx & 7])
	changed.emit()


## Swap two display-order entries (`mNW_swap_image_no`). Reorders without touching
## design contents.
func swap_player_order(a: int, b: int) -> void:
	var t := player_order[a & 7]
	player_order[a & 7] = player_order[b & 7]
	player_order[b & 7] = t
	changed.emit()


func save_player_slot(player_slot: int, design: DesignPattern) -> void:
	player[resolved_index(player_slot)].copy_from(design)
	changed.emit()


# --- Sable friendship -------------------------------------------------------

## Advance the day counter at most once per real calendar day (`aNNW_day_day`).
func tick_sable_day(today: String) -> void:
	if today == sable_last_date:
		return
	sable_last_date = today
	if sable_days < SABLE_DAYS_MAX:
		sable_days += 1
	sable_day_advanced.emit(sable_days)


# --- persistence -----------------------------------------------------------

func to_save() -> Dictionary:
	var p: Array = []
	for d in player:
		p.append(d.to_save())
	var s: Array = []
	for d in shop:
		s.append(d.to_save())
	var order: Array[int] = []
	for v in player_order:
		order.append(int(v))
	return {
		"player": p,
		"shop": s,
		"order": order,
		"sable_days": sable_days,
		"sable_last_date": sable_last_date,
		"sister_now": sister_now,
		"first_talk_done": first_talk_done,
		"listened": listened_flag,
		"trend_count": Array(trend_count),
		"trend_eligible": Array(trend_eligible),
		"trend_last_date": trend_last_date,
	}


func apply_snapshot(data: Variant) -> void:
	clear()
	if typeof(data) != TYPE_DICTIONARY:
		return
	var dict: Dictionary = data
	var p: Variant = dict.get("player", [])
	if p is Array:
		for i in mini((p as Array).size(), SLOT_COUNT):
			player[i] = DesignPattern.from_save((p as Array)[i])
	var s: Variant = dict.get("shop", [])
	if s is Array:
		for i in mini((s as Array).size(), SLOT_COUNT):
			shop[i] = DesignPattern.from_save((s as Array)[i])
	var order: Variant = dict.get("order", [])
	if order is Array and (order as Array).size() == SLOT_COUNT:
		for i in SLOT_COUNT:
			player_order[i] = int((order as Array)[i]) & 7
	sable_days = clampi(int(dict.get("sable_days", 0)), 0, SABLE_DAYS_MAX)
	sable_last_date = str(dict.get("sable_last_date", ""))
	sister_now = int(dict.get("sister_now", 0))
	first_talk_done = bool(dict.get("first_talk_done", false))
	listened_flag = bool(dict.get("listened", false))
	var tc: Variant = dict.get("trend_count", [])
	if tc is Array and (tc as Array).size() == SLOT_COUNT:
		for i in SLOT_COUNT:
			trend_count[i] = int((tc as Array)[i])
	var te: Variant = dict.get("trend_eligible", [])
	if te is Array and (te as Array).size() == SLOT_COUNT:
		for i in SLOT_COUNT:
			trend_eligible[i] = int((te as Array)[i]) & 1
	trend_last_date = str(dict.get("trend_last_date", ""))
