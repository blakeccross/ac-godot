class_name MaskCat
extends RefCounted

## Blanca, the cat with no face (`m_mask_cat.h`, `ac_npc_mask_cat`, `ac_npc_mask_cat2`). She rides
## the train into a town: always when the traveller is visiting, and every other trip when they
## come home (`Scene_ct` for `SCENE_START_DEMO3`, `mPr_FLAG_MASK_CAT_SCHEDULED`). She asks them
## to draw her a face (the design editor on a blank face, palette 15, `mDE_maskcat_init`), and
## the town keeps it with the painter's name (`Save_Get(mask_cat)`). With a face she takes the
## weekly visitor slot on days Gulliver isn't due (`mMC_check_birth`) until she has been talked
## to ten times or a week has passed (`mMC_check_delete`).
##
## `Game.mask_cat`: `{design, creator, cloth, talk_idx, day}`.

const TALK_MAX := 10
const KEEP_DAYS := 7
## `mDE_maskcat_init`: palette 15, every pixel colour 15.
const BLANK_PALETTE := 15
const BLANK_INDEX := 15
## The town talk (`aNMC_set_talk_info`).
const MSG_TOWN_FIRST := 0x31E4
const MSG_TOWN_AGAIN := 0x31E5


static func state() -> Dictionary:
	return Game.mask_cat if Game != null else {}


## `mDE_maskcat_init`: the face she arrives with.
static func blank_face() -> DesignPattern:
	var d := DesignPattern.blank()
	d.palette = BLANK_PALETTE
	d.pixels.fill(BLANK_INDEX)
	return d


static func face(s: Dictionary = state()) -> DesignPattern:
	var raw: Variant = s.get("design", {})
	if typeof(raw) != TYPE_DICTIONARY or (raw as Dictionary).is_empty():
		return blank_face()
	return DesignPattern.from_save(raw)


## `aNM2_chk_mask_texture`: something other than the blank colour was drawn.
static func is_drawn(d: DesignPattern) -> bool:
	if d == null:
		return false
	for px: int in d.pixels:
		if (px & 0xF) != BLANK_INDEX:
			return true
	return false


## `mMC_check_birth`: a face from someone and fewer than ten talks.
static func check_birth(s: Dictionary = state()) -> bool:
	return str(s.get("creator", "")) != "" and int(s.get("talk_idx", 0)) < TALK_MAX


## The face drawn on the train is the town's now (`mMC_set_time`).
static func store(d: DesignPattern, creator: String, today: int) -> void:
	var s: Dictionary = state()
	s["design"] = d.to_save()
	s["creator"] = creator
	s["talk_idx"] = 0
	s["day"] = today


## `mMC_mask_cat_init`, keeping the shirt she wears.
static func clear(s: Dictionary = state()) -> void:
	var cloth: int = int(s.get("cloth", -1))
	s.clear()
	s["cloth"] = cloth


## `mMC_check_delete`: gone after ten talks or more than a week either side of the drawing.
static func check_delete(today: int, s: Dictionary = state()) -> void:
	if str(s.get("creator", "")) == "":
		return
	var day: int = int(s.get("day", today))
	if int(s.get("talk_idx", 0)) >= TALK_MAX or today >= day + KEEP_DAYS or today <= day - KEEP_DAYS:
		clear(s)


## `Scene_ct` for the travel train: a visitor always meets her; a resident coming home meets
## her on alternate trips, half the time. Returns whether she rides, and updates `scheduled`
## (the resident's `mPr_FLAG_MASK_CAT_SCHEDULED`) through `out`.
static func rides_train(visitor: bool, scheduled: bool, roll: float, out: Dictionary) -> bool:
	if visitor:
		return true
	if scheduled:
		out["scheduled"] = false
		return false
	out["scheduled"] = roll < 0.5
	return roll < 0.5


## `aNMC_set_talk_info`: the first talk of the day moves her story on (0x31E4 + 4·idx), later
## talks pick one of three lines for where she is in it.
static func town_msg(first_today: bool, rng: RandomNumberGenerator, s: Dictionary = state()) -> int:
	var idx: int = int(s.get("talk_idx", 0))
	if first_today:
		s["talk_idx"] = idx + 1
		return MSG_TOWN_FIRST + 4 * idx
	return MSG_TOWN_AGAIN + 4 * (maxi(idx, 1) - 1) + rng.randi_range(0, 2)
