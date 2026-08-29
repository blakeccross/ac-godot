class_name Relationship
extends RefCounted

## Player ↔ one villager (`Anmmem_c`). Dialogue may query this; it does not own it.

signal milestone_reached(milestone: StringName)

const FRIENDSHIP_MIN := 0
## Original clamp is s8 0–127 (`mNpc_AddFriendship`). We keep the existing 0–255 range.
const FRIENDSHIP_MAX := 255
## `mNpc_GetAnimalMemoryBestFriend` rejects memories below 80.
const BEST_FRIEND_AT := 80
## Original friendship cap.
const KINDRED_AT := 127
const TALK_FIRST := 3
const TALK_REPEAT := 1
## Mail with a present is +3 (`mNpc` receive letter).
const GIFT_DELTA := 3
const HISTORY := 12

const MET := &"met"
const BEST_FRIEND := &"best_friend"
const KINDRED := &"kindred"
const FIRST_GIFT := &"first_gift"

const TALK_KIND_FIRST := &"first"
const TALK_KIND_TODAY := &"today"
const TALK_KIND_AGAIN := &"again"

var villager_id: StringName = &""
var friendship: int = 0
var last_spoke_day: String = ""
var talk_count: int = 0
var gift_count: int = 0
var talks: Array[Dictionary] = []
var gifts: Array[Dictionary] = []
var milestones: Array[StringName] = []


func talked_on(day_key: String) -> bool:
	return day_key != "" and last_spoke_day == day_key


func record_talk(day_key: String) -> int:
	var first_ever: bool = talk_count == 0
	var first_today: bool = not talked_on(day_key)
	var kind: StringName = TALK_KIND_TODAY
	if first_ever:
		kind = TALK_KIND_FIRST
	elif first_today:
		kind = TALK_KIND_AGAIN
	var delta: int = TALK_FIRST if first_today else TALK_REPEAT
	talk_count += 1
	last_spoke_day = day_key
	_push_talk(day_key, kind)
	add_friendship(delta)
	return delta


func record_gift(item_id: StringName, day_key: String) -> int:
	if item_id == &"":
		return 0
	gift_count += 1
	_push_gift(day_key, item_id)
	add_friendship(GIFT_DELTA)
	return GIFT_DELTA


func add_friendship(amount: int) -> void:
	set_friendship(friendship + amount)


func set_friendship(value: int) -> void:
	friendship = clampi(value, FRIENDSHIP_MIN, FRIENDSHIP_MAX)
	_refresh_milestones(true)


func has_milestone(milestone: StringName) -> bool:
	return milestone in milestones


func has_gifted(item_id: StringName) -> bool:
	if item_id == &"":
		return false
	for entry: Dictionary in gifts:
		if StringName(str(entry.get("item", ""))) == item_id:
			return true
	return false


func to_save() -> Dictionary:
	var marks: Array[String] = []
	for mark: StringName in milestones:
		marks.append(String(mark))
	return {
		"id": String(villager_id),
		"friendship": friendship,
		"last_spoke_day": last_spoke_day,
		"talk_count": talk_count,
		"gift_count": gift_count,
		"talks": talks.duplicate(true),
		"gifts": gifts.duplicate(true),
		"milestones": marks,
	}


func apply_snapshot(data: Dictionary) -> void:
	if data.has("id"):
		villager_id = StringName(str(data.get("id", "")))
	friendship = clampi(int(data.get("friendship", 0)), FRIENDSHIP_MIN, FRIENDSHIP_MAX)
	last_spoke_day = str(data.get("last_spoke_day", ""))
	talk_count = maxi(0, int(data.get("talk_count", 0)))
	gift_count = maxi(0, int(data.get("gift_count", 0)))
	talks = _dict_list(data.get("talks", []))
	gifts = _dict_list(data.get("gifts", []))
	milestones.clear()
	var raw: Variant = data.get("milestones", [])
	if typeof(raw) == TYPE_ARRAY:
		for entry: Variant in raw as Array:
			var mark := StringName(str(entry))
			if mark != &"" and mark not in milestones:
				milestones.append(mark)
	_refresh_milestones(false)


func _refresh_milestones(notify: bool) -> void:
	if talk_count >= 1:
		_unlock(MET, notify)
	if friendship >= BEST_FRIEND_AT:
		_unlock(BEST_FRIEND, notify)
	if friendship >= KINDRED_AT:
		_unlock(KINDRED, notify)
	if gift_count >= 1:
		_unlock(FIRST_GIFT, notify)


func _unlock(milestone: StringName, notify: bool) -> void:
	if milestone in milestones:
		return
	milestones.append(milestone)
	if notify:
		milestone_reached.emit(milestone)


func _push_talk(day_key: String, kind: StringName) -> void:
	talks.append({"day": day_key, "kind": String(kind)})
	_trim(talks)


func _push_gift(day_key: String, item_id: StringName) -> void:
	gifts.append({"day": day_key, "item": String(item_id)})
	_trim(gifts)


func _trim(history: Array[Dictionary]) -> void:
	while history.size() > HISTORY:
		history.remove_at(0)


func _dict_list(raw: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for entry: Variant in raw as Array:
		if typeof(entry) == TYPE_DICTIONARY:
			out.append((entry as Dictionary).duplicate(true))
	return out
