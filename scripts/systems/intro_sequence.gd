class_name IntroSequence
extends RefCounted

## Rover train character-creation flow (`ac_npc_guide`). Face math from
## `aNGD_set_pl_face_type` / `aNGD_check_talk_msg_no`. Not a C state port.

const FACE_TYPE_NUM := 8
const NAME_MAX_LEN := 8
const TOWN_MAX_LEN := 8

## Bit 3/2/1 = first three quiz answers (A sets the bit). Bit 0 = money “just a little”.
const FLAG_Q1 := 1 << 3
const FLAG_Q2 := 1 << 2
const FLAG_Q3 := 1 << 1
const FLAG_MONEY_SPARSE := 1 << 0

## `mPr_SEX_MALE` / `mPr_SEX_FEMALE` face tables from `aNGD_set_pl_face_type`.
const MALE_FACES: Array[int] = [5, 6, 1, 4, 0, 2, 7, 3]
const FEMALE_FACES: Array[int] = [0, 5, 2, 6, 4, 7, 3, 1]

const GENDER_MALE := &"male"
const GENDER_FEMALE := &"female"

signal prompt_requested(kind: StringName)
signal finished(identity: Dictionary)
signal cancelled

var player_name: String = ""
var town_name: String = ""
var gender: StringName = GENDER_MALE
var face: int = 0
var answer_flags: int = 0
var clock_ok: bool = true

var _rng: RandomNumberGenerator
var _done: bool = false


func _init(rng: RandomNumberGenerator = null) -> void:
	_rng = rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		_rng.randomize()


func reset() -> void:
	player_name = ""
	town_name = ""
	gender = GENDER_MALE
	face = 0
	answer_flags = 0
	clock_ok = true
	_done = false


static func clamp_name(text: String) -> String:
	var trimmed: String = text.strip_edges()
	if trimmed.is_empty():
		return ""
	return trimmed.substr(0, NAME_MAX_LEN)


static func clamp_town(text: String) -> String:
	var trimmed: String = text.strip_edges()
	if trimmed.is_empty():
		return ""
	return trimmed.substr(0, TOWN_MAX_LEN)


static func normalize_gender(value: Variant) -> StringName:
	var raw: String = str(value).to_lower()
	if raw == "female" or raw == "girl" or raw == "f":
		return GENDER_FEMALE
	return GENDER_MALE


## Decomp: bit0 clear → random; else table[gender][flags >> 1].
static func resolve_face(
	p_gender: StringName, flags: int, rng: RandomNumberGenerator = null
) -> int:
	if (flags & FLAG_MONEY_SPARSE) == 0:
		var roller: RandomNumberGenerator = rng
		if roller == null:
			roller = RandomNumberGenerator.new()
			roller.randomize()
		return roller.randi_range(0, FACE_TYPE_NUM - 1)
	var index: int = (flags >> 1) & (FACE_TYPE_NUM - 1)
	if p_gender == GENDER_FEMALE:
		return FEMALE_FACES[index]
	return MALE_FACES[index]


func or_answer_flag(mask: int) -> void:
	answer_flags |= mask


func set_player_name(text: String) -> bool:
	var next: String = clamp_name(text)
	if next.is_empty():
		return false
	player_name = next
	return true


func set_town_name(text: String) -> bool:
	var next: String = clamp_town(text)
	if next.is_empty():
		return false
	town_name = next
	return true


func set_gender(value: Variant) -> void:
	gender = normalize_gender(value)


func apply_dialogue_vars(vars: Dictionary) -> void:
	if vars.has("answer_flags"):
		answer_flags = int(vars["answer_flags"])
	if vars.has("gender"):
		set_gender(vars["gender"])
	if vars.has("player_name"):
		set_player_name(str(vars["player_name"]))
	if vars.has("town_name"):
		set_town_name(str(vars["town_name"]))


func handle_event(event: Dictionary) -> bool:
	## Returns true when the event needs a modal pause (`prompt_*`).
	var op := String(event.get("op", event.get("type", "")))
	match op:
		"set_var":
			var key := str(event.get("name", ""))
			match key:
				"gender":
					set_gender(event.get("value", GENDER_MALE))
				"answer_flags":
					answer_flags = int(event.get("value", 0))
				"player_name":
					set_player_name(str(event.get("value", "")))
				"town_name":
					set_town_name(str(event.get("value", "")))
			return false
		"or_var":
			var or_key := str(event.get("name", ""))
			if or_key == "answer_flags":
				or_answer_flag(int(event.get("mask", event.get("value", 0))))
			return false
		"set_gender":
			set_gender(event.get("value", GENDER_MALE))
			return false
		"prompt_clock":
			prompt_requested.emit(&"clock")
			return true
		"prompt_name":
			prompt_requested.emit(&"name")
			return true
		"prompt_town":
			prompt_requested.emit(&"town")
			return true
		"resolve_face":
			face = resolve_face(gender, answer_flags, _rng)
			return false
		"finish_intro":
			complete()
			return false
		_:
			return false


func identity() -> Dictionary:
	return {
		"player_name": player_name if player_name != "" else Game.DEFAULT_PLAYER_NAME,
		"town_name": town_name if town_name != "" else Game.DEFAULT_TOWN_NAME,
		"player_gender": String(gender),
		"player_face": face,
	}


func complete() -> void:
	if _done:
		return
	_done = true
	face = resolve_face(gender, answer_flags, _rng)
	finished.emit(identity())


func cancel() -> void:
	if _done:
		return
	_done = true
	cancelled.emit()
