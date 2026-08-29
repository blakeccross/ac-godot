class_name DialogueCondition
extends RefCounted

## Predicate on a `DialogueContext`. Dictionaries AND their keys. Empty = true.


static func matches(when: Variant, ctx: DialogueContext) -> bool:
	if when == null:
		return true
	if typeof(when) == TYPE_DICTIONARY:
		return _dict(when as Dictionary, ctx)
	if typeof(when) == TYPE_ARRAY:
		for entry: Variant in when as Array:
			if not matches(entry, ctx):
				return false
		return true
	return true


static func _dict(when: Dictionary, ctx: DialogueContext) -> bool:
	if when.is_empty():
		return true
	if when.has("not"):
		return not matches(when["not"], ctx)
	if when.has("all"):
		return matches(when["all"], ctx)
	if when.has("any"):
		var any_ok := false
		var opts: Variant = when["any"]
		if typeof(opts) == TYPE_ARRAY:
			for entry: Variant in opts as Array:
				if matches(entry, ctx):
					any_ok = true
					break
		return any_ok
	if when.has("chance"):
		if ctx == null or not ctx.roll(int(when["chance"])):
			return false
	if ctx == null:
		return when.is_empty()
	if when.has("already_talked") and bool(when["already_talked"]) != ctx.already_talked:
		return false
	if when.has("friendship_gte") and ctx.friendship < int(when["friendship_gte"]):
		return false
	if when.has("friendship_lt") and ctx.friendship >= int(when["friendship_lt"]):
		return false
	if when.has("mood") and ctx.mood_name() != str(when["mood"]).to_lower():
		return false
	if when.has("time_of_day") and ctx.time_of_day_name() != str(when["time_of_day"]).to_lower():
		return false
	if when.has("hour_gte") and ctx.hour < int(when["hour_gte"]):
		return false
	if when.has("hour_lt") and ctx.hour >= int(when["hour_lt"]):
		return false
	if when.has("hours"):
		var span: Variant = when["hours"]
		if typeof(span) == TYPE_ARRAY and (span as Array).size() >= 2:
			var a: int = int((span as Array)[0])
			var b: int = int((span as Array)[1])
			if not ClockService.hour_in_window(ctx.hour, a, b):
				return false
	if when.has("weekday"):
		if not _weekday_ok(when["weekday"], ctx.weekday):
			return false
	if when.has("season") and ctx.season_name() != str(when["season"]).to_lower():
		return false
	if when.has("weather") and ctx.weather_name() != str(when["weather"]).to_lower():
		return false
	if when.has("has_item"):
		if ctx.count_item(StringName(str(when["has_item"]))) <= 0:
			return false
	if when.has("item_count_gte"):
		var spec: Variant = when["item_count_gte"]
		if typeof(spec) == TYPE_DICTIONARY:
			var item_id := StringName(str((spec as Dictionary).get("item", "")))
			var need: int = int((spec as Dictionary).get("count", 1))
			if ctx.count_item(item_id) < need:
				return false
	if when.has("held_item") and String(ctx.held_item) != str(when["held_item"]):
		return false
	if when.has("personality") and ctx.personality_name() != str(when["personality"]).to_lower():
		return false
	if when.has("islander") and bool(when["islander"]) != ctx.islander:
		return false
	if when.has("var_eq"):
		var spec: Variant = when["var_eq"]
		if typeof(spec) == TYPE_DICTIONARY:
			var key := str((spec as Dictionary).get("name", ""))
			if str(ctx.get_var(key)) != str((spec as Dictionary).get("value", "")):
				return false
	if when.has("var_gte"):
		var spec: Variant = when["var_gte"]
		if typeof(spec) == TYPE_DICTIONARY:
			var key := str((spec as Dictionary).get("name", ""))
			if int(ctx.get_var(key, 0)) < int((spec as Dictionary).get("value", 0)):
				return false
	if when.has("var"):
		if not ctx.has_var(str(when["var"])):
			return false
	return true


static func _weekday_ok(want: Variant, weekday: int) -> bool:
	if typeof(want) == TYPE_ARRAY:
		for entry: Variant in want as Array:
			if _weekday_ok(entry, weekday):
				return true
		return false
	if typeof(want) == TYPE_INT or typeof(want) == TYPE_FLOAT:
		return weekday == int(want)
	var name := str(want).to_lower()
	var names := ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
	var idx: int = names.find(name)
	if idx >= 0:
		return weekday == idx
	return false
