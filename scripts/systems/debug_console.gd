class_name DebugConsole
extends RefCounted

## Slash-command parser for the play HUD debug overlay (weather, season, give, …).
## Not an autoload — the overlay owns one instance. Logic stays testable without UI.

const COMMANDS: PackedStringArray = ["help", "weather", "season", "give", "time", "bells", "clear"]
const WEATHER_KINDS: PackedStringArray = ["clear", "rain", "snow", "sakura"]
const INTENSITY_NAMES: PackedStringArray = ["none", "light", "normal", "heavy"]
const SEASON_ARGS: PackedStringArray = ["spring", "summer", "autumn", "fall", "winter", "next"]

var history: PackedStringArray = []


func execute(raw: String) -> String:
	var line: String = raw.strip_edges()
	if line.begins_with("/"):
		line = line.substr(1).strip_edges()
	if line.is_empty():
		return ""
	_push_history(raw.strip_edges())
	var parts: PackedStringArray = line.split(" ", false)
	if parts.is_empty():
		return ""
	var cmd: String = String(parts[0]).to_lower()
	var args: PackedStringArray = parts.slice(1)
	match cmd:
		"help", "?":
			return _cmd_help()
		"weather":
			return _cmd_weather(args)
		"season":
			return _cmd_season(args)
		"give":
			return _cmd_give(args)
		"time":
			return _cmd_time(args)
		"bells":
			return _cmd_bells(args)
		"clear":
			return "__clear__"
		_:
			return "Unknown command '%s'. Type help." % cmd


## Completions for the token under the cursor (Minecraft-style Tab).
func suggestions(line: String) -> PackedStringArray:
	var parsed: Dictionary = _token_at_end(line)
	var token: String = String(parsed["token"])
	var index: int = int(parsed["index"])
	var prior: PackedStringArray = parsed["prior"] as PackedStringArray
	if index == 0:
		return _filter_prefix(COMMANDS, token)
	var cmd: String = String(prior[0]).to_lower()
	if cmd.begins_with("/"):
		cmd = cmd.substr(1)
	match cmd:
		"weather":
			if index == 1:
				return _filter_prefix(WEATHER_KINDS, token)
			if index == 2:
				return _filter_prefix(INTENSITY_NAMES, token)
		"season":
			if index == 1:
				return _filter_prefix(SEASON_ARGS, token)
		"give":
			if index == 1:
				return _filter_prefix(_item_ids(), token)
		"time":
			if index == 1:
				return _filter_prefix(["+1h", "+1d", "6", "12", "18", "0"], token)
		"bells":
			if index == 1:
				return _filter_prefix(["1000", "10000", "99999"], token)
	return PackedStringArray()


## Apply Tab: fill the longest common prefix, or the sole match.
func autocomplete(line: String) -> String:
	var matches: PackedStringArray = suggestions(line)
	if matches.is_empty():
		return line
	var parsed: Dictionary = _token_at_end(line)
	var prefix: String = String(parsed["prefix"])
	var fill: String = matches[0] if matches.size() == 1 else _common_prefix(matches)
	if fill.is_empty():
		return line
	## Sole match gets a trailing space so the next arg is ready to type.
	var spacer: String = " " if matches.size() == 1 else ""
	return prefix + fill + spacer


## Replace the current token with a concrete suggestion (Tab cycle).
func fill_suggestion(line: String, suggestion: String) -> String:
	var parsed: Dictionary = _token_at_end(line)
	return String(parsed["prefix"]) + suggestion


func history_prev(current: String, index: int) -> Dictionary:
	## Returns `{text, index}` walking older entries. `index` -1 means “at live line”.
	if history.is_empty():
		return {"text": current, "index": -1}
	var next_i: int = index
	if next_i < 0:
		next_i = history.size() - 1
	else:
		next_i = maxi(next_i - 1, 0)
	return {"text": String(history[next_i]), "index": next_i}


func history_next(current: String, index: int, live: String) -> Dictionary:
	if history.is_empty() or index < 0:
		return {"text": live, "index": -1}
	var next_i: int = index + 1
	if next_i >= history.size():
		return {"text": live, "index": -1}
	return {"text": String(history[next_i]), "index": next_i}


func _push_history(line: String) -> void:
	if line.is_empty():
		return
	if not history.is_empty() and String(history[history.size() - 1]) == line:
		return
	history.append(line)
	if history.size() > 64:
		history = history.slice(history.size() - 64)


func _cmd_help() -> String:
	return "\n".join([
		"Commands:",
		"  weather <clear|rain|snow|sakura> [none|light|normal|heavy]",
		"  season <spring|summer|autumn|winter|next>",
		"  give <item_id> [count]",
		"  time [+1h|+1d|HH|HH:MM]",
		"  bells <amount>",
		"  clear / help",
		"Tab completes. Up/Down recall history.",
	])


func _cmd_weather(args: PackedStringArray) -> String:
	if args.is_empty():
		return "Weather: %s (intensity %d)" % [String(Game.weather), Game.weather_intensity]
	var kind: String = String(args[0]).to_lower()
	if kind not in WEATHER_KINDS:
		return "Unknown weather '%s'. Use clear, rain, snow, or sakura." % kind
	var intensity: int = -1
	if args.size() >= 2:
		intensity = _parse_intensity(String(args[1]))
		if intensity < 0:
			return "Unknown intensity '%s'. Use none, light, normal, or heavy." % String(args[1])
	Game.set_weather(StringName(kind), intensity)
	return "Weather set to %s (intensity %d)." % [String(Game.weather), Game.weather_intensity]


func _cmd_season(args: PackedStringArray) -> String:
	if args.is_empty():
		return "Season: %s" % Clock.season_name()
	var name: String = String(args[0]).to_lower()
	if name == "next":
		Clock.advance_season()
		return "Advanced to %s." % Clock.season_name()
	if name == "fall":
		name = "autumn"
	var season: int = _parse_season(name)
	if season < 0:
		return "Unknown season '%s'. Use spring, summer, autumn, winter, or next." % String(args[0])
	Clock.jump_to_season(season as ClockService.Season)
	return "Season set to %s (%04d-%02d-%02d)." % [Clock.season_name(), Clock.year, Clock.month, Clock.day]


func _cmd_give(args: PackedStringArray) -> String:
	if args.is_empty():
		return "Usage: give <item_id> [count]"
	var item_id := StringName(String(args[0]).to_lower())
	var data: ItemData = ItemCatalog.get_item(item_id)
	if data == null:
		return "Unknown item '%s'." % String(args[0])
	var count: int = 1
	if args.size() >= 2:
		if not String(args[1]).is_valid_int():
			return "Count must be an integer."
		count = maxi(1, int(args[1]))
	var left: int = Game.inventory.add(data, count)
	var given: int = count - left
	if given <= 0:
		return "Pockets full — could not add %s." % String(item_id)
	if left > 0:
		return "Added %d× %s (%d did not fit)." % [given, _item_label(data), left]
	return "Added %d× %s." % [given, _item_label(data)]


func _cmd_time(args: PackedStringArray) -> String:
	if args.is_empty():
		return Clock.format_clock()
	var arg: String = String(args[0]).to_lower()
	if arg == "+1h" or arg == "+1hour":
		Clock.advance_minutes(60)
		return "Advanced 1 hour → %s" % Clock.format_clock()
	if arg == "+1d" or arg == "+1day":
		Clock.advance_minutes(60 * 24)
		return "Advanced 1 day → %s" % Clock.format_clock()
	if arg.begins_with("+") and arg.ends_with("h") and arg.substr(1, arg.length() - 2).is_valid_int():
		var hours: int = int(arg.substr(1, arg.length() - 2))
		Clock.advance_minutes(hours * 60)
		return "Advanced %dh → %s" % [hours, Clock.format_clock()]
	if arg.begins_with("+") and arg.ends_with("d") and arg.substr(1, arg.length() - 2).is_valid_int():
		var days: int = int(arg.substr(1, arg.length() - 2))
		Clock.advance_minutes(days * 60 * 24)
		return "Advanced %dd → %s" % [days, Clock.format_clock()]
	var hour: int = 0
	var minute: int = 0
	if ":" in arg:
		var bits: PackedStringArray = arg.split(":")
		if bits.size() != 2 or not String(bits[0]).is_valid_int() or not String(bits[1]).is_valid_int():
			return "Usage: time [+1h|+1d|HH|HH:MM]"
		hour = int(bits[0])
		minute = int(bits[1])
	elif arg.is_valid_int():
		hour = int(arg)
	else:
		return "Usage: time [+1h|+1d|HH|HH:MM]"
	if hour < 0 or hour > 23 or minute < 0 or minute > 59:
		return "Hour must be 0–23 and minute 0–59."
	Clock.apply_snapshot({
		"year": Clock.year,
		"month": Clock.month,
		"day": Clock.day,
		"hour": hour,
		"minute": minute,
		"second": 0,
	})
	return "Time set → %s" % Clock.format_clock()


func _cmd_bells(args: PackedStringArray) -> String:
	if args.is_empty():
		return "Bells: %d" % Game.inventory.wallet
	if not String(args[0]).is_valid_int():
		return "Usage: bells <amount>"
	var amount: int = clampi(int(args[0]), 0, Inventory.WALLET_MAX)
	Game.inventory.set_wallet(amount)
	return "Bells set to %d." % Game.inventory.wallet


func _item_label(data: ItemData) -> String:
	if data.display_name.strip_edges() != "":
		return data.display_name
	return String(data.id)


func _parse_intensity(name: String) -> int:
	match name.to_lower():
		"none", "0":
			return int(Weather.Intensity.NONE)
		"light", "1":
			return int(Weather.Intensity.LIGHT)
		"normal", "2":
			return int(Weather.Intensity.NORMAL)
		"heavy", "3":
			return int(Weather.Intensity.HEAVY)
		_:
			return -1


func _parse_season(name: String) -> int:
	match name:
		"spring":
			return int(ClockService.Season.SPRING)
		"summer":
			return int(ClockService.Season.SUMMER)
		"autumn", "fall":
			return int(ClockService.Season.AUTUMN)
		"winter":
			return int(ClockService.Season.WINTER)
		_:
			return -1


func _item_ids() -> PackedStringArray:
	ItemCatalog.ensure_loaded()
	var ids: Array[String] = []
	for item: ItemData in ItemCatalog.all_items():
		if item != null and item.id != &"":
			ids.append(String(item.id))
	ids.sort()
	return PackedStringArray(ids)


func _filter_prefix(options: PackedStringArray, token: String) -> PackedStringArray:
	var needle: String = token.to_lower()
	var out: PackedStringArray = []
	for opt: String in options:
		if needle.is_empty() or String(opt).to_lower().begins_with(needle):
			out.append(opt)
	return out


func _token_at_end(line: String) -> Dictionary:
	## Strip a leading `/` for command matching but keep spacing for rewrite.
	var working: String = line
	var slash: bool = working.begins_with("/")
	if slash:
		working = working.substr(1)
	var parts: PackedStringArray = working.split(" ", false)
	var ends_space: bool = line.ends_with(" ")
	if working.strip_edges().is_empty():
		return {"token": "", "index": 0, "prior": PackedStringArray(), "prefix": "/" if slash else ""}
	if ends_space:
		return {
			"token": "",
			"index": parts.size(),
			"prior": parts,
			"prefix": line,
		}
	var token: String = String(parts[parts.size() - 1])
	var prior: PackedStringArray = parts.slice(0, parts.size() - 1)
	var prefix: String = line.substr(0, line.length() - token.length())
	return {"token": token, "index": prior.size(), "prior": prior, "prefix": prefix}


func _common_prefix(values: PackedStringArray) -> String:
	if values.is_empty():
		return ""
	var prefix: String = String(values[0])
	for i: int in range(1, values.size()):
		var s: String = String(values[i])
		var n: int = mini(prefix.length(), s.length())
		var j: int = 0
		while j < n and prefix[j].to_lower() == s[j].to_lower():
			j += 1
		prefix = prefix.substr(0, j)
		if prefix.is_empty():
			return ""
	return prefix
