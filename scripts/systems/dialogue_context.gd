class_name DialogueContext
extends RefCounted

## Snapshot the runner evaluates. Built from Clock / Game / villager; tests can fill it.

var player_name: String = "Player"
var town_name: String = "Town"
var speaker_name: String = ""
## `mNpc_GetLooks2Sex`: 0 male, 1 female, 2 other → nameplate tint in `m_msg_appear`.
var speaker_sex: int = 2
var catchphrase: String = ""
var species: String = ""
var hour: int = 12
var weekday: int = 0
var month: int = 1
var day: int = 1
var year: int = 2001
var minute: int = 0
var time_of_day: ClockService.TimeOfDay = ClockService.TimeOfDay.DAY
var season: ClockService.Season = ClockService.Season.WINTER
var weather: StringName = &"clear"
var friendship: int = 0
var talk_count: int = 0
var gift_count: int = 0
var already_talked: bool = false
var mood: VillagerState.Mood = VillagerState.Mood.NORMAL
var held_item: StringName = &""
var personality: StringName = &""
## `mNpc_GetNpcSoundSpec` value (2–4 for villagers). Drives animalese bank/pitch.
var sound_spec: int = 2
## `VOICE_MODE_*` — animalese / click / silent.
var voice_mode: int = DialogueVoice.Mode.ANIMALESE
## `VOICE_STATUS_*`; -1 → derive from `mood`.
var voice_status: int = -1
var islander: bool = false
var days_since_talk: int = -1
var inventory: Inventory
var vars: Dictionary = {}
var items: Dictionary = {}
var rng: RandomNumberGenerator
var item0: String = ""
var island: String = ""
## Delivery / letter target for first-job (and similar) lines.
var recipient: String = ""
var frees: PackedStringArray = PackedStringArray()
var milestones: Array[StringName] = []
var gifted_items: Array[StringName] = []

## Substitution slots that must not remain after `substitute` (style tags excluded).
const SLOT_KEYS := [
	"player",
	"speaker",
	"name",
	"catchphrase",
	"species",
	"town",
	"island",
	"year",
	"month",
	"day",
	"hour",
	"minute",
	"weekday",
	"ampm",
	"item0",
	"item",
	"recipient",
]


static func from_game(villager: VillagerData = null, state: VillagerState = null) -> DialogueContext:
	var ctx := DialogueContext.new()
	ctx.player_name = Game.player_name
	ctx.town_name = Game.town_name
	ctx.hour = Clock.hour
	ctx.weekday = Clock.weekday()
	ctx.month = Clock.month
	ctx.day = Clock.day
	ctx.year = Clock.year
	ctx.minute = Clock.minute
	ctx.time_of_day = Clock.time_of_day()
	ctx.season = Clock.season()
	ctx.weather = Game.weather
	ctx.inventory = Game.inventory
	ctx.vars = Game.dialogue_vars
	if Game.inventory != null:
		ctx.held_item = Game.inventory.equipment_id
	if villager != null:
		ctx.speaker_name = villager.display_name
		ctx.catchphrase = villager.catchphrase
		ctx.species = String(villager.species)
		ctx.islander = villager.islander
		if villager.personality != null:
			ctx.personality = villager.personality.id
			ctx.speaker_sex = villager.personality.message_sex()
			ctx.sound_spec = DialogueVoice.sound_spec_for_looks(villager.personality.looks)
			ctx.voice_mode = DialogueVoice.Mode.ANIMALESE
		else:
			ctx.voice_mode = DialogueVoice.Mode.CLICK
	else:
		ctx.voice_mode = DialogueVoice.Mode.CLICK
	if state != null:
		var bond: Relationship = state.relationship
		if bond == null:
			bond = Relationship.new()
		ctx.friendship = bond.friendship
		ctx.talk_count = bond.talk_count
		ctx.gift_count = bond.gift_count
		ctx.milestones = bond.milestones.duplicate()
		ctx.gifted_items = _gifted_ids(bond)
		ctx.already_talked = bond.talked_on(
			"%04d-%02d-%02d" % [Clock.year, Clock.month, Clock.day]
		)
		ctx.mood = state.mood
		ctx.days_since_talk = _days_since(bond.last_spoke_day, ctx.year, ctx.month, ctx.day)
		if ctx.voice_status < 0:
			ctx.voice_status = int(DialogueVoice.status_for_mood(state.mood))
	if Game.first_job != null and Game.first_job.is_active() and Game.first_job.recipient_id != &"":
		ctx.recipient = Game.first_job.recipient_name()
	return ctx


func time_of_day_name() -> String:
	return ClockService.TIME_OF_DAY_NAMES[int(time_of_day)].to_lower()


func season_name() -> String:
	return ClockService.SEASON_NAMES[int(season)].to_lower()


func weather_name() -> String:
	return String(weather).to_lower()


func mood_name() -> String:
	match mood:
		VillagerState.Mood.HAPPY:
			return "happy"
		VillagerState.Mood.ANGRY:
			return "angry"
		VillagerState.Mood.SAD:
			return "sad"
		VillagerState.Mood.SLEEPY:
			return "sleepy"
		VillagerState.Mood.PITFALL:
			return "pitfall"
		_:
			return "normal"


func personality_name() -> String:
	return String(personality).to_lower()


func count_item(item_id: StringName) -> int:
	if item_id == &"":
		return 0
	if inventory != null:
		return inventory.count_of(item_id)
	return int(items.get(item_id, 0))


func get_var(key: String, default_value: Variant = 0) -> Variant:
	if vars.has(key):
		return vars[key]
	return default_value


func has_var(key: String) -> bool:
	return vars.has(key)


func has_milestone(milestone: StringName) -> bool:
	return milestone in milestones


func has_gifted(item_id: StringName) -> bool:
	return item_id != &"" and item_id in gifted_items


func set_var(key: String, value: Variant) -> void:
	if key == "":
		return
	vars[key] = value


func roll(percent: int) -> bool:
	if percent >= 100:
		return true
	if percent <= 0:
		return false
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	return rng.randi_range(0, 99) < percent


func substitute(text: String) -> String:
	var out: String = MessageWindowChrome._normalize_punct(text)
	var used: PackedStringArray = slot_keys_in(out)
	out = out.replace("{player}", player_name)
	out = out.replace("{speaker}", speaker_name)
	out = out.replace("{name}", speaker_name)
	out = out.replace("{catchphrase}", catchphrase)
	out = out.replace("{species}", species)
	out = out.replace("{town}", town_name)
	out = out.replace("{island}", island)
	out = out.replace("{year}", str(year))
	out = out.replace("{month}", str(month))
	out = out.replace("{day}", str(day))
	out = out.replace("{hour}", str(hour))
	out = out.replace("{minute}", "%02d" % minute)
	out = out.replace("{weekday}", ClockService.WEEKDAYS[weekday] if weekday >= 0 and weekday < 7 else "")
	out = out.replace("{ampm}", "AM" if hour < 12 else "PM")
	out = out.replace("{item0}", item0)
	out = out.replace("{item}", item0)
	out = out.replace("{recipient}", recipient)
	## Always clear free0…free19 so unused slots cannot leak as braces.
	for i: int in 20:
		var free_val: String = frees[i] if i < frees.size() else ""
		out = out.replace("{free%d}" % i, free_val)
	## Imported banks keep `SETSELSTR` as `{choice:N}` until `select.json` is present.
	var search_from := 0
	while true:
		var start: int = out.find("{choice:", search_from)
		if start < 0:
			break
		var end: int = out.find("}", start)
		if end < 0:
			break
		var num_str: String = out.substr(start + 8, end - start - 8)
		if num_str.is_valid_int():
			var label: String = DialogueCatalog.choice_label(int(num_str))
			out = out.substr(0, start) + label + out.substr(end + 1)
			search_from = start + label.length()
		else:
			search_from = end + 1
	_report_empty_slots(used)
	_report_leftover_slots(out)
	return out


static func slot_keys_in(text: String) -> PackedStringArray:
	## Named substitution slots present in `text` (ignores `{c:}` / `{s:}` / `{choice:}`).
	var found: PackedStringArray = PackedStringArray()
	var seen: Dictionary = {}
	var search_from := 0
	while true:
		var start: int = text.find("{", search_from)
		if start < 0:
			break
		var end: int = text.find("}", start)
		if end < 0:
			break
		var inner: String = text.substr(start + 1, end - start - 1)
		search_from = end + 1
		if inner.begins_with("c:") or inner.begins_with("s:") or inner.begins_with("choice:"):
			continue
		if not _is_slot_key(inner):
			continue
		if seen.has(inner):
			continue
		seen[inner] = true
		found.append(inner)
	return found


static func leftover_slot_keys(text: String) -> PackedStringArray:
	return slot_keys_in(text)


static func _is_slot_key(inner: String) -> bool:
	if inner in SLOT_KEYS:
		return true
	if inner.begins_with("free") and inner.length() > 4 and inner.substr(4).is_valid_int():
		var idx: int = int(inner.substr(4))
		return idx >= 0 and idx < 20
	return false


func _slot_value(key: String) -> String:
	match key:
		"player":
			return player_name
		"speaker", "name":
			return speaker_name
		"catchphrase":
			return catchphrase
		"species":
			return species
		"town":
			return town_name
		"island":
			return island
		"year":
			return str(year)
		"month":
			return str(month)
		"day":
			return str(day)
		"hour":
			return str(hour)
		"minute":
			return "%02d" % minute
		"weekday":
			return ClockService.WEEKDAYS[weekday] if weekday >= 0 and weekday < 7 else ""
		"ampm":
			return "AM" if hour < 12 else "PM"
		"item0", "item":
			return item0
		"recipient":
			return recipient
		_:
			if key.begins_with("free") and key.length() > 4 and key.substr(4).is_valid_int():
				var idx: int = int(key.substr(4))
				if idx >= 0 and idx < frees.size():
					return frees[idx]
			return ""


func _report_empty_slots(used: PackedStringArray) -> void:
	for key: String in used:
		## Clock / ampm always have a value; skip soft defaults that authors rely on.
		if key in ["year", "month", "day", "hour", "minute", "weekday", "ampm"]:
			continue
		if _slot_value(key).strip_edges() != "":
			continue
		push_error("DialogueContext: {%s} used but value is empty" % key)


func _report_leftover_slots(text: String) -> void:
	for key: String in leftover_slot_keys(text):
		push_error("DialogueContext: unsubstituted {%s} left in dialogue" % key)


static func _days_since(last: String, year: int, month: int, day: int) -> int:
	if last == "":
		return -1
	var parts: PackedStringArray = last.split("-")
	if parts.size() < 3:
		return -1
	var then_unix: int = int(
		Time.get_unix_time_from_datetime_dict(
			{"year": int(parts[0]), "month": int(parts[1]), "day": int(parts[2]), "hour": 12}
		)
	)
	var now_unix: int = int(
		Time.get_unix_time_from_datetime_dict({"year": year, "month": month, "day": day, "hour": 12})
	)
	return int((now_unix - then_unix) / 86400.0)


static func _gifted_ids(bond: Relationship) -> Array[StringName]:
	var out: Array[StringName] = []
	if bond == null:
		return out
	for entry: Dictionary in bond.gifts:
		var item_id := StringName(str(entry.get("item", "")))
		if item_id != &"" and item_id not in out:
			out.append(item_id)
	return out
