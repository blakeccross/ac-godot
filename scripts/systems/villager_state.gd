class_name VillagerState
extends RefCounted

## Per-villager save fields (mood, patience). Friendship lives on `relationship`.

enum Mood { NORMAL, HAPPY, ANGRY, SAD, SLEEPY, PITFALL }
enum Patience { MILDLY_ANNOYED, ANNOYED, NORMAL }

const FRIENDSHIP_MIN := Relationship.FRIENDSHIP_MIN
const FRIENDSHIP_MAX := Relationship.FRIENDSHIP_MAX
const TALK_FIRST := Relationship.TALK_FIRST
const TALK_REPEAT := Relationship.TALK_REPEAT

var villager_id: StringName = &""
var relationship: Relationship = Relationship.new()
var mood: Mood = Mood.NORMAL
var patience: Patience = Patience.NORMAL
## `Animal_c.is_home` — indoors (hidden outdoors / visible in NPC room).
var is_home: bool = false

var friendship: int:
	get:
		return relationship.friendship if relationship != null else 0
	set(value):
		_bond().set_friendship(value)

var last_spoke_day: String:
	get:
		return relationship.last_spoke_day if relationship != null else ""
	set(value):
		_bond().last_spoke_day = value


func talked_on(day_key: String) -> bool:
	return _bond().talked_on(day_key)


func record_talk(day_key: String) -> int:
	var delta: int = _bond().record_talk(day_key)
	if mood == Mood.NORMAL:
		mood = Mood.HAPPY
	return delta


func add_friendship(amount: int) -> void:
	_bond().add_friendship(amount)


func to_save() -> Dictionary:
	_bond().villager_id = villager_id
	return {
		"id": String(villager_id),
		"friendship": friendship,
		"last_spoke_day": last_spoke_day,
		"mood": int(mood),
		"patience": int(patience),
		"is_home": is_home,
		"relationship": _bond().to_save(),
	}


func apply_snapshot(data: Dictionary) -> void:
	if data.has("id"):
		villager_id = StringName(str(data.get("id", "")))
	mood = int(data.get("mood", Mood.NORMAL)) as Mood
	patience = int(data.get("patience", Patience.NORMAL)) as Patience
	is_home = bool(data.get("is_home", false))
	var nested: Variant = data.get("relationship", {})
	if typeof(nested) == TYPE_DICTIONARY and not (nested as Dictionary).is_empty():
		_bond().apply_snapshot(nested as Dictionary)
	else:
		_bond().apply_snapshot(
			{
				"id": String(villager_id),
				"friendship": int(data.get("friendship", 0)),
				"last_spoke_day": str(data.get("last_spoke_day", "")),
			}
		)
	_bond().villager_id = villager_id


func _bond() -> Relationship:
	if relationship == null:
		relationship = Relationship.new()
	if villager_id != &"":
		relationship.villager_id = villager_id
	return relationship
