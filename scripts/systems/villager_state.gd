class_name VillagerState
extends RefCounted

## Per-villager save fields (mood, patience). Friendship lives on `relationship`.

enum Mood { NORMAL, HAPPY, ANGRY, SAD, SLEEPY, PITFALL }
enum Patience { MILDLY_ANNOYED, ANNOYED, NORMAL }

const FRIENDSHIP_MIN := Relationship.FRIENDSHIP_MIN
const FRIENDSHIP_MAX := Relationship.FRIENDSHIP_MAX
const TALK_FIRST := Relationship.TALK_FIRST
const TALK_REPEAT := Relationship.TALK_REPEAT
## `mNpc_FEEL_ALL_NUM`; orders at or above it are ignored.
const FEEL_ALL_NUM := 9
## `FRAMES_PER_MINUTE` in decomp logic ticks.
const FEEL_TICKS_PER_MINUTE := 3600

var villager_id: StringName = &""
var relationship: Relationship = Relationship.new()
var mood: Mood = Mood.NORMAL
## Ticks left on a message-set feel (`condition_info.feel_tim`, not saved). 0 = untimed.
var feel_ticks: int = 0
var patience: Patience = Patience.NORMAL
## `Animal_c.is_home` — indoors (hidden outdoors / visible in NPC room).
var is_home: bool = false
## `conversation_flags.fish/insect_complete_talk` — this villager already congratulated the
## player on the finished collection (`mNpc_Set*CompleteTalk`).
var fish_complete_talk: bool = false
var insect_complete_talk: bool = false
## Able Sisters design worn (`Animal_c.cloth == RSV_CLOTH` + `cloth_original_id`, and
## `umbrella_id` in `ITM_MY_ORG_UMBRELLA0..3`): -1 = none, else mannequin / stand 0-3.
## Spread by `NeedleworkTrend`.
var cloth_design: int = -1
var umbrella_design: int = -1
## `Animal_c.catchphrase` once the player changed it (`aQMgr_order_change_gobi`); empty = default.
var catchphrase: String = ""
## Shirt the villager was given and changed into (`Animal_c.cloth` after `npc_chg_cloth`);
## empty = their own (`VillagerData.default_cloth`).
var cloth_id: StringName = &""

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
	return _bond().record_talk(day_key)


## `aNPC_set_feel_info`: a message sets the feel (`mNpc_FEEL_*`) for `minutes`; the same
## feel again adds time up to ten minutes; normal clears the timer. `mNpc_FEEL_PITFALL`
## becomes normal and the annoyed feels (6–8, `mNpc_FEEL_UZAI_*`) read as angry here.
func set_feel(feel: int, minutes: int) -> void:
	if feel <= 0 or feel >= FEEL_ALL_NUM:
		if feel == 0:
			mood = Mood.NORMAL
			feel_ticks = 0
		return
	var next: Mood = Mood.ANGRY
	match feel:
		1:
			next = Mood.HAPPY
		2:
			next = Mood.ANGRY
		3:
			next = Mood.SAD
		4:
			next = Mood.SLEEPY
		5:
			next = Mood.NORMAL
	if next != mood:
		mood = next
		feel_ticks = 0 if next == Mood.NORMAL else minutes * FEEL_TICKS_PER_MINUTE
	else:
		feel_ticks = mini(feel_ticks + minutes * FEEL_TICKS_PER_MINUTE, 10 * FEEL_TICKS_PER_MINUTE)


## `aNPC_check_feel_tim`: a timed feel runs out back to normal.
func tick_feel(ticks: int) -> void:
	if feel_ticks <= 0:
		return
	feel_ticks = maxi(feel_ticks - ticks, 0)
	if feel_ticks == 0:
		mood = Mood.NORMAL


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
		"fish_complete_talk": fish_complete_talk,
		"insect_complete_talk": insect_complete_talk,
		"cloth_design": cloth_design,
		"umbrella_design": umbrella_design,
		"catchphrase": catchphrase,
		"cloth_id": String(cloth_id),
		"relationship": _bond().to_save(),
	}


func apply_snapshot(data: Dictionary) -> void:
	if data.has("id"):
		villager_id = StringName(str(data.get("id", "")))
	mood = int(data.get("mood", Mood.NORMAL)) as Mood
	patience = int(data.get("patience", Patience.NORMAL)) as Patience
	is_home = bool(data.get("is_home", false))
	fish_complete_talk = bool(data.get("fish_complete_talk", false))
	insect_complete_talk = bool(data.get("insect_complete_talk", false))
	cloth_design = clampi(int(data.get("cloth_design", -1)), -1, 3)
	umbrella_design = clampi(int(data.get("umbrella_design", -1)), -1, 3)
	catchphrase = str(data.get("catchphrase", ""))
	cloth_id = StringName(str(data.get("cloth_id", "")))
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
