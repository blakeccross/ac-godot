class_name VillagerState
extends RefCounted

## Per-villager save fields (friendship, last speak, mood). Not `Animal_c`.

enum Mood { NORMAL, HAPPY, ANGRY, SAD, SLEEPY, PITFALL }
enum Patience { MILDLY_ANNOYED, ANNOYED, NORMAL }

const FRIENDSHIP_MIN := 0
const FRIENDSHIP_MAX := 255
const TALK_FIRST := 3
const TALK_REPEAT := 1

var villager_id: StringName = &""
var friendship: int = 0
var last_spoke_day: String = ""
var mood: Mood = Mood.NORMAL
var patience: Patience = Patience.NORMAL


func talked_on(day_key: String) -> bool:
	return day_key != "" and last_spoke_day == day_key


func record_talk(day_key: String) -> int:
	var first: bool = not talked_on(day_key)
	var delta: int = TALK_FIRST if first else TALK_REPEAT
	add_friendship(delta)
	last_spoke_day = day_key
	if mood == Mood.NORMAL:
		mood = Mood.HAPPY
	return delta


func add_friendship(amount: int) -> void:
	friendship = clampi(friendship + amount, FRIENDSHIP_MIN, FRIENDSHIP_MAX)


func to_save() -> Dictionary:
	return {
		"id": String(villager_id),
		"friendship": friendship,
		"last_spoke_day": last_spoke_day,
		"mood": int(mood),
		"patience": int(patience),
	}


func apply_snapshot(data: Dictionary) -> void:
	if data.has("id"):
		villager_id = StringName(str(data.get("id", "")))
	friendship = clampi(int(data.get("friendship", 0)), FRIENDSHIP_MIN, FRIENDSHIP_MAX)
	last_spoke_day = str(data.get("last_spoke_day", ""))
	mood = int(data.get("mood", Mood.NORMAL)) as Mood
	patience = int(data.get("patience", Patience.NORMAL)) as Patience
