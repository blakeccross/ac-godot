class_name DebugConsole
extends RefCounted

## Slash-command parser for the play HUD debug overlay (weather, season, give, …).
## Not an autoload — the overlay owns one instance. Logic stays testable without UI.

const COMMANDS: PackedStringArray = [
	"help", "weather", "season", "give", "time", "bells", "house", "event", "fortune", "bug", "shop",
	"clear"
]
const SHOP_ARGS: PackedStringArray = ["status", "sales", "visitor", "restock", "turnips"]
const EVENT_ARGS: PackedStringArray = ["list", "start", "stop", "goto", "special"]
const HOUSE_ARGS: PackedStringArray = ["size", "basement", "build", "loan", "statue", "goki", "neglect"]
const HOUSE_SIZES: PackedStringArray = ["small", "medium", "large", "upper"]
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
		"house":
			return _cmd_house(args)
		"event", "events":
			return _cmd_event(args)
		"fortune", "destiny":
			return _cmd_fortune(args)
		"bug", "insect":
			return _cmd_bug(args)
		"shop":
			return _cmd_shop(args)
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
		"event", "events":
			if index == 1:
				return _filter_prefix(EVENT_ARGS, token)
			if index == 2:
				return _filter_prefix(_event_ids(String(prior[1]).to_lower()), token)
		"shop":
			if index == 1:
				return _filter_prefix(SHOP_ARGS, token)
		"house":
			if index == 1:
				return _filter_prefix(HOUSE_ARGS, token)
			if index == 2 and String(prior[1]).to_lower() == "size":
				return _filter_prefix(HOUSE_SIZES, token)
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
		"  house [size <small|medium|large|upper> | basement | build | loan <n> | statue | goki [n] | neglect [days]]",
		"  event [list | start <id> | stop [id] | goto <id> | special <id>]",
		"  fortune [normal|popular|unpopular|bad_luck|money_luck|goods_luck]",
		"  bug <id> [count]  (spawn insects in front of the player)",
		"  shop [status | sales <n> | visitor | restock | turnips]",
		"  clear / help",
		"Tab completes. Up/Down recall history.",
	])


## Spawns field insects a few metres ahead of the player, on the ground there, in the bug's
## first habitat — for watching a program without waiting on `aSOI_insect_set`.
func _cmd_bug(args: PackedStringArray) -> String:
	if args.is_empty():
		return "Usage: bug <id> [count], e.g. bug grasshopper 3"
	var bug: BugData = BugCatalog.get_bug(StringName(String(args[0]).to_lower()))
	if bug == null:
		return "Unknown bug '%s'." % String(args[0])
	var tree: SceneTree = Game.get_tree()
	var world := World.find(tree)
	var player := Player.find(tree)
	if world == null or player == null or world.layout == null:
		return "Bugs need the outdoor field."
	var count: int = clampi(int(args[1]) if args.size() > 1 else 1, 1, BugField.MAX_ACTORS)
	var habitat: BugData.Habitat = (
		bug.habitats[0] as BugData.Habitat if not bug.habitats.is_empty() else BugData.Habitat.GROUND
	)
	var yaw: float = player.facing_yaw()
	var ahead := Vector3(sin(yaw), 0.0, cos(yaw))
	var side := Vector3(ahead.z, 0.0, -ahead.x)
	var spawned: int = 0
	for i: int in count:
		var at: Vector3 = player.global_position + ahead * 3.0 + side * (float(i) - (count - 1) * 0.5)
		at.y = FieldCollision.ground_y_at(world.layout, world.grid, at)
		if world.bugs.spawn(bug, habitat, at) != null:
			spawned += 1
	return "Spawned %d %s." % [spawned, bug.id]


## Today's `Private_c.destiny` — normally set by Katrina / the New Year shrine (not built
## yet); bad luck makes a full dash trip on flat ground.
func _cmd_fortune(args: PackedStringArray) -> String:
	var names: PackedStringArray = PackedStringArray(
		["normal", "popular", "unpopular", "bad_luck", "money_luck", "goods_luck"]
	)
	if args.is_empty():
		return "Fortune: %s" % names[int(Game.destiny())]
	var want: int = names.find(String(args[0]).to_lower())
	if want < 0:
		return "Unknown fortune '%s'. Use %s." % [String(args[0]), ", ".join(names)]
	Game.set_destiny(want)
	return "Fortune set to %s for today." % names[want]


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


func _cmd_event(args: PackedStringArray) -> String:
	var events: EventCalendar = Game.events
	var sub: String = "list" if args.is_empty() else String(args[0]).to_lower()
	if sub == "list":
		return "\n".join(events.describe())
	if sub == "stop" and args.size() < 2:
		events.clear_forced()
		_sync_events()
		return "Cleared all forced events."
	if args.size() < 2:
		return "Usage: event [list | start <id> | stop [id] | goto <id> | special <id>]"
	var id: StringName = StringName(String(args[1]).to_lower())
	if not EventSchedule.has_id(id):
		return "Unknown event '%s'. Tab lists ids." % String(id)
	match sub:
		"start":
			events.force(id)
			_sync_events()
			return "Started %s (forced until 'event stop %s')." % [EventSchedule.label(id), String(id)]
		"stop":
			events.unforce(id)
			_sync_events()
			if events.is_active(id):
				return "%s is still on the schedule; 'event goto' another date to leave it." % EventSchedule.label(id)
			return "Stopped %s." % EventSchedule.label(id)
		"goto":
			var target: Dictionary = events.next_start(id, EventCalendar.date_from_clock())
			if target.is_empty():
				return "%s has no upcoming start in the calendar. Try 'event start %s'." % [
					EventSchedule.label(id), String(id)
				]
			Clock.set_datetime(
				int(target["year"]), int(target["month"]), int(target["day"]), int(target["hour"])
			)
			return "%s begins → %s" % [EventSchedule.label(id), Clock.format_clock()]
		"special":
			if not events.schedule_special(id, EventCalendar.date_from_clock()):
				return "'%s' is not a special visit. Use: %s" % [
					String(id), ", ".join(PackedStringArray(EventCalendar.SPECIAL_POOL))
				]
			_sync_events()
			return "%s visits now." % EventSchedule.label(id)
	return "Usage: event [list | start <id> | stop [id] | goto <id> | special <id>]"


func _sync_events() -> void:
	Game.events.sync(EventCalendar.date_from_clock())


func _event_ids(sub: String) -> PackedStringArray:
	if sub == "special":
		return PackedStringArray(EventCalendar.SPECIAL_POOL)
	var out: PackedStringArray = []
	for id: StringName in EventSchedule.ids():
		out.append(String(id))
	return out


## Nook's store: level, renovation, hours, raffle and Stalk Market state.
func _cmd_shop(args: PackedStringArray) -> String:
	var shop: ShopBook = Game.shops
	var sub: String = String(args[0]).to_lower() if not args.is_empty() else "status"
	match sub:
		"sales":
			if args.size() < 2 or not String(args[1]).is_valid_int():
				return "Usage: shop sales <amount>"
			shop.plus_sales(int(args[1]))
		"visitor":
			shop.set_visitor()
		"restock":
			shop.restock(ShopBook.NOOK_ID)
			Game.refresh_shop_set()
		"turnips":
			var week: PackedStringArray = []
			shop.kabu.update(Clock.year, Clock.month, Clock.day)
			for d: int in 7:
				week.append("%s %d" % [String(ClockService.WEEKDAYS[d]).substr(0, 3), shop.kabu.price_on(d)])
			return "Turnips (%s): %s" % [KabuMarket.Trend.keys()[shop.kabu.trend], ", ".join(week)]
		"status":
			pass
		_:
			return "Usage: shop [status | sales <n> | visitor | restock | turnips]"
	return "%s · level %d (earned %d) · sales %d · %s %d:00-%d:00 · renewal day %d · visitor %s" % [
		ShopMail.store_name(shop.nook_level()), shop.nook_level(), shop.real_level(),
		shop.sales_sum(), ShopBook.Status.keys()[shop.nook_status()], shop.nook_open_hour(),
		shop.nook_close_hour(), shop.renewal_day(), "yes" if shop.has_visitor() else "no",
	]


func _cmd_bells(args: PackedStringArray) -> String:
	if args.is_empty():
		return "Bells: %d" % Game.inventory.wallet
	if not String(args[0]).is_valid_int():
		return "Usage: bells <amount>"
	var amount: int = clampi(int(args[0]), 0, Inventory.WALLET_MAX)
	Game.inventory.set_wallet(amount)
	return "Bells set to %d." % Game.inventory.wallet


func _cmd_house(args: PackedStringArray) -> String:
	var house: House = Game.interiors.player_house()
	if house == null:
		return "No player house."
	if args.is_empty():
		return "House: %s (next %s), basement %s, loan %d, order %04d-%02d-%02d%s" % [
			HOUSE_SIZES[mini(int(house.size_tier), HOUSE_SIZES.size() - 1)],
			HOUSE_SIZES[mini(int(house.next_size_tier), HOUSE_SIZES.size() - 1)],
			"yes" if house.has_basement else "no",
			Game.inventory.loan,
			house.order_year,
			house.order_month,
			house.order_day,
			", statue" if HouseUpgrade.is_statue(house) else "",
		]
	match String(args[0]).to_lower():
		"size":
			var idx: int = HOUSE_SIZES.find(String(args[1]).to_lower()) if args.size() >= 2 else -1
			if idx < 0:
				return "Usage: house size <small|medium|large|upper>"
			house.size_tier = idx as House.SizeTier
			house.next_size_tier = idx as House.SizeTier
			if idx < int(House.SizeTier.MEDIUM):
				house.has_basement = false
			Game.interiors.refresh_player_rooms()
			return "House is now %s. Re-enter the world to see the outside." % HOUSE_SIZES[idx]
		"basement":
			house.has_basement = not house.has_basement
			Game.interiors.refresh_player_rooms()
			return "Basement %s." % ("built" if house.has_basement else "removed")
		"build":
			## Make a pending order stale so it lands, as if you had started the game tomorrow.
			var prior: int = house.order_day
			house.order_day = 0 if prior != 0 else 32
			if not Game.check_rehouse_order():
				house.order_day = prior
				return "Nothing is on order."
			return "The order landed. Talk to Tom Nook."
		"loan":
			if args.size() < 2 or not String(args[1]).is_valid_int():
				return "Usage: house loan <amount>"
			Game.inventory.set_loan(maxi(int(args[1]), 0))
			return "Loan set to %d." % Game.inventory.loan
		"goki":
			if args.size() < 2 or not String(args[1]).is_valid_int():
				return "Cockroaches waiting: %d (last played %d days ago)." % [house.goki_count, HouseGoki.days_away(house)]
			house.goki_count = HouseGoki.clamp_count(int(args[1]))
			return "%d cockroaches are waiting in the walls." % house.goki_count
		"neglect":
			var days: int = int(args[1]) if args.size() >= 2 and String(args[1]).is_valid_int() else 10
			var then: Dictionary = Time.get_datetime_dict_from_unix_time(
				int(Time.get_unix_time_from_datetime_dict({"year": Clock.year, "month": Clock.month, "day": Clock.day, "hour": 12})) - days * 86400
			)
			house.goki_year = int(then["year"])
			house.goki_month = int(then["month"])
			house.goki_day = int(then["day"])
			HouseGoki.decide_family_count(house)
			return "Away %d days: %d cockroaches waiting." % [days, house.goki_count]
		"statue":
			house.size_tier = House.SizeTier.UPPER
			house.next_size_tier = House.SizeTier.UPPER
			Game.inventory.set_loan(0)
			return "House is at its final size with no loan. Talk to Tom Nook about the statue."
		_:
			return "Usage: house [size|basement|build|loan|statue]"


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
