class_name CompleteTalk
extends RefCounted

## "You completed the fish / insect collection" comments. A villager mentions it once per
## collection, and doing so is what puts the fish weathervane / insect plaque on the player's
## house (`mPr_*CompleteTalk`, `ac_quest_talk_greeting.c`, `ac_my_house.c` joints 1/3/5).
##
## `Game.complete_flags` mirrors `Private_c.complete_fish_insect_flags`: per collection a pair
## of bits — *complete at start* (`base`) and *villager has commented* (`talk`).

const FISH := 0
const INSECT := 1

## `MSG_10700` (insect) / `MSG_10718` (fish); three variants per looks type.
const MSG_INSECT := 10700
const MSG_FISH := 10718
const VARIANTS := 3

const KIND_FISH := &"fish"
const KIND_INSECT := &"insect"


static func _kind(type: int) -> StringName:
	return KIND_FISH if type == FISH else KIND_INSECT


static func _bit_base(type: int) -> int:
	return type * 2


static func _bit_talk(type: int) -> int:
	return type * 2 + 1


## `mSM_CHECK_ALL_FISH_GET` / `..._INSECT_GET`.
static func collection_complete(type: int) -> bool:
	var log: SpeciesLog = Game.species_log
	if log == null:
		return false
	var kind: StringName = _kind(type)
	var total: int = log.page_total(kind)
	return total > 0 and log.page_count(kind) >= total


## `mPr_StartSetCompleteTalkInfo`: at game start, note collections that are already done.
static func start_set_info() -> void:
	for type: int in [FISH, INSECT]:
		if collection_complete(type):
			Game.complete_flags |= 1 << _bit_base(type)


## `mPr_GetTalkPermission` gated on the collection being complete.
static func permission(type: int) -> bool:
	if not collection_complete(type):
		return false
	var flags: int = Game.complete_flags
	return ((flags >> _bit_base(type)) & 1) == 0 or ((flags >> _bit_talk(type)) & 1) == 0


## `mPr_CheckFishCompleteTalk` / `..._InsectCompleteTalk` — drives the house decorations.
static func talked(type: int) -> bool:
	return ((Game.complete_flags >> _bit_talk(type)) & 1) == 1


static func _villager_told(state: VillagerState, type: int) -> bool:
	return state != null and (state.fish_complete_talk if type == FISH else state.insect_complete_talk)


static func _mark(state: VillagerState, type: int) -> void:
	Game.complete_flags |= 1 << _bit_talk(type)
	if state == null:
		return
	if type == FISH:
		state.fish_complete_talk = true
	else:
		state.insect_complete_talk = true


## The villager's opening line when a collection is finished and they have not yet said so,
## in the decomp's order (both done → coin flip; else insect, then fish). Marks the flags
## and returns the `msg_no`, or −1 when the normal greeting should play.
static func try_greeting(looks: int, state: VillagerState, rng: RandomNumberGenerator) -> int:
	var fish_ok: bool = permission(FISH) and not _villager_told(state, FISH)
	var insect_ok: bool = permission(INSECT) and not _villager_told(state, INSECT)
	var type: int = -1
	if fish_ok and insect_ok:
		type = rng.randi_range(0, 3) & 1
		## `type == 0` is the insect line.
		type = INSECT if type == 0 else FISH
	elif insect_ok:
		type = INSECT
	elif fish_ok:
		type = FISH
	if type < 0:
		return -1
	var base: int = MSG_INSECT if type == INSECT else MSG_FISH
	_mark(state, type)
	return base + clampi(looks, 0, 5) * VARIANTS + rng.randi_range(0, VARIANTS - 1)
