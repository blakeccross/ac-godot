class_name DialogueContext
extends RefCounted

## Snapshot the runner evaluates. Built from Clock / Game / villager; tests can fill it.

var player_name: String = "Player"
var town_name: String = "Town"
var speaker_name: String = ""
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
var already_talked: bool = false
var mood: VillagerState.Mood = VillagerState.Mood.NORMAL
var held_item: StringName = &""
var personality: StringName = &""
var islander: bool = false
var days_since_talk: int = -1
var inventory: Inventory
var vars: Dictionary = {}
var items: Dictionary = {}
var rng: RandomNumberGenerator
var item0: String = ""
var island: String = ""
var frees: PackedStringArray = PackedStringArray()


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
	if state != null:
		ctx.friendship = state.friendship
		ctx.already_talked = state.talked_on(
			"%04d-%02d-%02d" % [Clock.year, Clock.month, Clock.day]
		)
		ctx.mood = state.mood
		ctx.days_since_talk = _days_since(state.last_spoke_day, ctx.year, ctx.month, ctx.day)
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
	var out: String = text
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
	for i: int in mini(frees.size(), 20):
		out = out.replace("{free%d}" % i, frees[i])
	return out


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
