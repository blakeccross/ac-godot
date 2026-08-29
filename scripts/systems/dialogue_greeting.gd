class_name DialogueGreeting
extends RefCounted

## Looks + meet-time + weather pick of a starting `msg_no` (`aQMgr_get_hello_msg_no`).
## Jumps into the imported bank when present; otherwise `looks_greeting`.

const KIND := 3
const FALLBACK_ID := &"looks_greeting"

const MEET_FIRST := 0
const MEET_AGAIN := 1
const MEET_TODAY := 2
const MEET_LONG := 3
const MEET_REALLY_LONG := 4

const TIME_MORNING := 0
const TIME_DAY := 1
const TIME_EVENING := 2
const TIME_NIGHT := 3

## `l_hello_fine_msg_tbl` / rain / snow (`ac_quest_talk_greeting.c`).
const FINE := [1213, 1357, 1285, 1501, 1645, 1429, 1573, 1717]
const RAIN := [1213, 3099, 3027, 1501, 1645, 1429, 1573, 1717]
const SNOW := [1213, 3243, 3171, 1501, 1645, 1429, 1573, 1717]
const GRAD := [4644, 4788, 4716, 4716, 4716, 4716, 4716, 4716]
const ISLAND_FINE := [13400, 13575, 13551, 13647, 13647, 13647, 13647, 13647]
const ISLAND_KIND := [1, 3, 1, 1, 1, 1, 1, 1]
const ANGRY := [3315, 3320, 3325, 3330, 3335, 3340]
const SAD := [3345, 3350, 3355, 3360, 3365, 3370]
const SLEEPY := [3375, 3380, 3385, 3390, 3395, 3400]
const PITFALL := 8327


static func conversation(villager: VillagerData, state: VillagerState, ctx: DialogueContext = null) -> DialogueData:
	var snap: DialogueContext = ctx if ctx != null else DialogueContext.from_game(villager, state)
	_ensure_rng(snap)
	var msg_no: int = hello_msg_no(villager, state, snap)
	var imported: DialogueData = DialogueCatalog.conversation(StringName("msg_%d" % msg_no))
	if imported != null:
		return imported
	return fallback_conversation()


static func hello_msg_no(villager: VillagerData, state: VillagerState, ctx: DialogueContext) -> int:
	_ensure_rng(ctx)
	var looks: int = _looks(villager)
	var meet: int = meet_type(state, ctx)
	if ctx.mood == VillagerState.Mood.PITFALL:
		return _random_looks(PITFALL, looks, KIND, ctx)
	if meet != MEET_FIRST:
		if ctx.mood == VillagerState.Mood.ANGRY:
			return ANGRY[looks] + _roll(5, ctx)
		if ctx.mood == VillagerState.Mood.SAD:
			return SAD[looks] + _roll(5, ctx)
		if ctx.mood == VillagerState.Mood.SLEEPY:
			return SLEEPY[looks] + _roll(5, ctx)
	if ctx.mood == VillagerState.Mood.HAPPY:
		return _hello_offset(GRAD[meet], looks, ctx.hour, KIND, ctx)
	if villager != null and villager.islander:
		var kind_count: int = ISLAND_KIND[meet] if meet >= 0 and meet < ISLAND_KIND.size() else 1
		return _hello_offset(ISLAND_FINE[meet], looks, ctx.hour, kind_count, ctx)
	var table: Array = FINE
	match ctx.weather_name():
		"rain":
			table = RAIN
		"snow":
			table = SNOW
	return _hello_offset(int(table[meet]), looks, ctx.hour, KIND, ctx)


static func msg_offset(base_msg: int, looks: int, hour: int, variant: int, kind_count: int = KIND) -> int:
	return base_msg + looks * kind_count * 4 + time_kind(hour) * kind_count + variant


static func meet_type(state: VillagerState, ctx: DialogueContext) -> int:
	if state == null or state.last_spoke_day == "":
		return MEET_FIRST
	if ctx.already_talked:
		return MEET_AGAIN
	var days: int = ctx.days_since_talk
	if days >= 60:
		return MEET_REALLY_LONG
	if days >= 14:
		return MEET_LONG
	return MEET_TODAY


static func time_kind(hour: int) -> int:
	if hour >= 12 and hour < 17:
		return TIME_DAY
	if hour >= 17:
		return TIME_EVENING
	if hour >= 0 and hour < 5:
		return TIME_NIGHT
	return TIME_MORNING


static func fallback_conversation() -> DialogueData:
	var data: DialogueData = DialogueCatalog.conversation(FALLBACK_ID)
	if data != null:
		return data
	return DialogueData.from_dict(
		{
			"id": "looks_greeting",
			"start": "start",
			"nodes": {
				"start": {"type": "line", "text": "Hello!"},
			},
		}
	)


static func bank_available() -> bool:
	return FileAccess.file_exists("res://assets/generated/dialogue/index.json")


static func _hello_offset(base_msg: int, looks: int, hour: int, kind_count: int, ctx: DialogueContext) -> int:
	return msg_offset(base_msg, looks, hour, _roll(kind_count, ctx), kind_count)


static func _random_looks(base_msg: int, looks: int, kind_count: int, ctx: DialogueContext) -> int:
	return base_msg + looks * kind_count + _roll(kind_count, ctx)


static func _looks(villager: VillagerData) -> int:
	if villager != null and villager.personality != null:
		return clampi(int(villager.personality.looks), 0, 5)
	return int(VillagerPersonality.Looks.LAZY)


static func _roll(kind_count: int, ctx: DialogueContext) -> int:
	if kind_count <= 1:
		return 0
	return ctx.rng.randi_range(0, kind_count - 1)


static func _ensure_rng(ctx: DialogueContext) -> void:
	if ctx == null:
		return
	if ctx.rng == null:
		ctx.rng = RandomNumberGenerator.new()
		ctx.rng.randomize()
