class_name DebugConsole
extends RefCounted

## Slash-command parser for the play HUD debug overlay (weather, season, give, …).
## Not an autoload — the overlay owns one instance. Logic stays testable without UI.

const SHOP_ARGS: PackedStringArray = ["status", "sales", "visitor", "restock", "turnips"]
const EVENT_ARGS: PackedStringArray = ["list", "start", "stop", "goto", "special"]
const HOUSE_ARGS: PackedStringArray = ["size", "basement", "build", "loan", "statue", "goki", "neglect", "roof"]
const HOUSE_SIZES: PackedStringArray = ["small", "medium", "large", "upper"]
const WEATHER_KINDS: PackedStringArray = ["clear", "rain", "snow", "sakura"]
const INTENSITY_NAMES: PackedStringArray = ["none", "light", "normal", "heavy"]
const LIGHTHOUSE_ARGS: PackedStringArray = ["status", "start", "lit", "clear"]
const RESETTI_ARGS: PackedStringArray = ["off", "on", "disable", "enable", "1", "2", "3", "4", "5", "6", "7", "8"]
const SEASON_ARGS: PackedStringArray = ["spring", "summer", "autumn", "fall", "winter", "next"]

var history: PackedStringArray = []

## Every command: its name (and aliases) → the `_cmd_*` that runs it with the words after it.
var _commands: Dictionary[String, Callable]


func _init() -> void:
	_commands = {
		"help": _cmd_help,
		"?": _cmd_help,
		"weather": _cmd_weather,
		"season": _cmd_season,
		"give": _cmd_give,
		"equip": _cmd_equip,
		"bridge": _cmd_bridge,
		"drop": _cmd_drop,
		"reflect": _cmd_reflect,
		"xmas": _cmd_xmas,
		"ball": _cmd_ball,
		"digup": _cmd_digup,
		"throwfish": _cmd_throwfish,
		"mailbox": _cmd_mailbox,
		"fx": _cmd_fx,
		"twirl": _cmd_twirl,
		"wish": _cmd_wish,
		"feel": _cmd_feel,
		"cam": _cmd_cam,
		"leave": _cmd_leave,
		"manpu": _cmd_manpu,
		"axebreak": _cmd_axebreak,
		"release": _cmd_release,
		"time": _cmd_time,
		"bells": _cmd_bells,
		"house": _cmd_house,
		"place": _cmd_place,
		"event": _cmd_event,
		"events": _cmd_event,
		"fortune": _cmd_fortune,
		"destiny": _cmd_fortune,
		"bug": _cmd_bug,
		"insect": _cmd_bug,
		"shop": _cmd_shop,
		"lighthouse": _cmd_lighthouse,
		"balloon": _cmd_balloon,
		"rainbow": _cmd_rainbow,
		"tune": _cmd_tune,
		"map": _cmd_map,
		"catalog": _cmd_catalog,
		"abd": _cmd_abd,
		"repay": _cmd_repay,
		"board": _cmd_board,
		"sting": _cmd_sting,
		"town": _cmd_town,
		"moneyrock": _cmd_moneyrock,
		"fengshui": _cmd_fengshui,
		"wisp": _cmd_wisp,
		"blanca": _cmd_blanca,
		"golden": _cmd_golden,
		"treasure": _cmd_treasure,
		"calendar": _cmd_calendar,
		"mom": _cmd_mom,
		"birthday": _cmd_birthday,
		"diary": _cmd_diary,
		"tan": _cmd_tan,
		"snowballs": _cmd_snowballs,
		"snowman": _cmd_snowman,
		"mushrooms": _cmd_mushrooms,
		"signboard": _cmd_signboard,
		"meteor": _cmd_meteor,
		"shells": _cmd_shells,
		"weeds": _cmd_weeds,
		"resetti": _cmd_resetti,
		"exercise": _cmd_exercise,
		"pitfall": _cmd_pitfall,
		"island": _cmd_island,
		"ride": _cmd_ride,
		"cannon": _cmd_cannon,
		"popper": _cmd_popper,
		"shine": _cmd_shine,
		"costume": _cmd_costume,
		"glow": _cmd_glow,
		"clear": _cmd_clear,
	}


## Command names for tab completion (aliases like `?` left out).
func command_names() -> PackedStringArray:
	var out := PackedStringArray()
	for name: String in _commands:
		if name.is_valid_identifier():
			out.append(name)
	return out


## The running tree; the console is a `RefCounted` the overlay owns, so it asks the engine.
static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


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
	var run: Callable = _commands.get(cmd, Callable())
	if not run.is_valid():
		return "Unknown command '%s'. Type help." % cmd
	return run.call(args)


## Town tune: `tune` plays it, `tune open` opens the editor, `tune reset` restores the default.
func _cmd_tune(args: PackedStringArray) -> String:
	var sub: String = String(args[0]).to_lower() if not args.is_empty() else "play"
	match sub:
		"open":
			var tree := _tree()
			var ui: TownTuneOverlay = TownTuneOverlay.find(tree)
			if ui == null:
				return "No tune editor in this scene."
			ui.open()
			return "Tune editor open."
		"reset":
			Game.town.town_tune = TownTune.default_notes()
			return "Town tune reset to the default."
	Audio.play_melody(Game.town.town_tune)
	return "Playing the town tune."


## Completions for the token under the cursor (Minecraft-style Tab).
func suggestions(line: String) -> PackedStringArray:
	var parsed: Token = _token_at_end(line)
	var token: String = parsed.text
	var index: int = parsed.index
	var prior: PackedStringArray = parsed.prior
	if index == 0:
		return _filter_prefix(command_names(), token)
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
		"lighthouse":
			if index == 1:
				return _filter_prefix(LIGHTHOUSE_ARGS, token)
		"resetti":
			if index == 1:
				return _filter_prefix(RESETTI_ARGS, token)
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
	var prefix: String = _token_at_end(line).prefix
	var fill: String = matches[0] if matches.size() == 1 else _common_prefix(matches)
	if fill.is_empty():
		return line
	## Sole match gets a trailing space so the next arg is ready to type.
	var spacer: String = " " if matches.size() == 1 else ""
	return prefix + fill + spacer


## Replace the current token with a concrete suggestion (Tab cycle).
func fill_suggestion(line: String, suggestion: String) -> String:
	return _token_at_end(line).prefix + suggestion


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


func history_next(index: int, live: String) -> Dictionary:
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


func _cmd_help(_args: PackedStringArray) -> String:
	return "\n".join([
		"Commands:",
		"  weather <clear|rain|snow|sakura> [none|light|normal|heavy]",
		"  season <spring|summer|autumn|winter|next>",
		"  give <item_id> [count]",
		"  time [+1h|+1d|HH|HH:MM]",
		"  bells <amount>",
		"  house [size <small|medium|large|upper> | basement | build | loan <n> | statue [built [rank]] | goki [n] | neglect [days]]",
		"  event [list | start <id> | stop [id] | goto <id> | special <id>]",
		"  fortune [normal|popular|unpopular|bad_luck|money_luck|goods_luck]",
		"  bug <id> [count]  (spawn insects in front of the player)",
		"  shop [status | sales <n> | visitor | restock | turnips]",
		"  lighthouse [status | start | lit | clear]  (Tortimer's lighthouse quest)",
		"  sting [on|off|mosquito]  (bee sting, set the swollen face, or a mosquito bite)",
		"  town [perfect]  (rate the town now)",
		"  weeds [n|clear]  (sow weeds now, or clear them all)",
		"  resetti [1-8|off|on]  (summon him, or keep him from appearing after a reset)",
		"  exercise <0-17>  (a radio exercise move)",
		"  pitfall [auto|villager]  (bury one under the player, or the nearest villager)",
		"  clear / help",
		"Tab completes. Up/Down recall history.",
	])


## `resetti` summons him as after reset number N. `off` / `disable` keeps him from appearing
## after an unsaved quit (saved immediately); `on` / `enable` brings that back.
func _cmd_resetti(args: PackedStringArray) -> String:
	var sub: String = String(args[0]).to_lower() if not args.is_empty() else ""
	if sub == "off" or sub == "disable":
		SaveService.set_resetti_disabled(true)
		load("res://scenes/world/resetti.gd").dismiss_all(_tree())
		return "Resetti disabled."
	if sub == "on" or sub == "enable":
		SaveService.set_resetti_disabled(false)
		return "Resetti enabled."
	## Mr. Resetti now, as after reset number N (1-8; default the next one).
	var tree := _tree()
	var player := tree.get_first_node_in_group(Player.GROUP) as Node3D if tree != null else null
	var world := World.find(tree) if tree != null else null
	if player == null or world == null:
		return "Resetti needs the outdoor field."
	Game.resident.reset_count = int(args[0]) if not args.is_empty() and String(args[0]).is_valid_int() else Game.resident.reset_count + 1
	Game.reset_flag = true
	load("res://scenes/world/resetti.gd").spawn(world.get_node("Characters"), player)
	return "Reset #%d." % Game.resident.reset_count


## Tortimer hands the lighthouse job out on his January / February vacation (`ac_ev_soncho2`);
## `start` gives it today without him, `lit` throws tonight's switch.
func _cmd_lighthouse(args: PackedStringArray) -> String:
	var book: LighthouseBook = Game.lighthouse
	match String(args[0]).to_lower() if not args.is_empty() else "status":
		"start":
			book.start_quest_now()
		"lit":
			if not book.in_nights(Clock.year, Clock.month, Clock.day):
				return "Not a quest night."
			book.switch_on_now()
		"clear":
			book.clear()
		"status":
			pass
		_:
			return "Usage: lighthouse [status | start | lit | clear]"
	var ordinal: int = EventDates.ordinal(Clock.year, Clock.month, Clock.day)
	return "Lighthouse: period %s, nights lit %s, lamp %s, door %s" % [
		LighthouseBook.Period.keys()[book.period_on(ordinal)],
		String.num_int64(book.nights_lit, 2).lpad(LighthouseBook.NIGHT_COUNT, "0"),
		"on" if book.lamp_on_now() else "off",
		"open" if book.door_open_now() else "shut",
	]


## Spawns field insects a few metres ahead of the player, on the ground there, in the bug's
## first habitat — for watching a program without waiting on `aSOI_insect_set`.
## `balloon` launches a present balloon now; `balloon near` starts it just upwind of you.
func _cmd_balloon(args: PackedStringArray) -> String:
	var tree: SceneTree = Game.get_tree()
	var sky: BalloonSky = BalloonSky.find(tree)
	if sky == null:
		return "Balloons need the outdoor field."
	if sky.balloon != null:
		return "A balloon is already out."
	var b: Balloon = sky.launch()
	if args.size() > 0 and String(args[0]).to_lower() == "near":
		var player := Player.find(tree)
		if player != null:
			var yaw: float = Game.wind.yaw()
			b.start_near(player.global_position - Vector3(sin(yaw), 0.0, cos(yaw)) * 8.0)
	return "Balloon launched (wind %d°, power %.2f)." % [int(rad_to_deg(Game.wind.yaw())), Game.wind.power()]


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
	if bug.type_index == Ant.TYPE:
		return _cmd_ants(bug, world, player)
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


## Ants swarm on food: on the candy or spoiled turnip lying in the player's acre
## (`drop candy` first).
func _cmd_ants(bug: BugData, world: Node, player: Node3D) -> String:
	var acre: Vector2i = BugHabitats.acre_of_world_pos(world.grid, player.global_position)
	for area: int in [BugSpawnScheduler.AREA_ON_CANDY, BugSpawnScheduler.AREA_ON_TRASH]:
		var sites: Array[BugHabitats.Site] = BugHabitats.sites_for_spawn_area(
			area, world.layout, world.grid, acre, func(_c: Vector2i) -> bool: return false, false
		)
		if not sites.is_empty() and world.bugs.spawn(bug, BugData.Habitat.GROUND, sites[0].anchor) != null:
			return "Ants on the food at %s." % sites[0].cell
	return "Ants need candy or a spoiled turnip on the ground here (drop candy)."


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
		return "Weather: %s (intensity %d)" % [String(Game.town.weather), Game.town.weather_intensity]
	var kind: String = String(args[0]).to_lower()
	if kind not in WEATHER_KINDS:
		return "Unknown weather '%s'. Use clear, rain, snow, or sakura." % kind
	var intensity: int = -1
	if args.size() >= 2:
		intensity = _parse_intensity(String(args[1]))
		if intensity < 0:
			return "Unknown intensity '%s'. Use none, light, normal, or heavy." % String(args[1])
	Game.set_weather(StringName(kind), intensity)
	return "Weather set to %s (intensity %d)." % [String(Game.town.weather), Game.town.weather_intensity]


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
		return "Usage: give <id> [count]"
	var id := StringName(String(args[0]).to_lower())
	var data: ItemData = ItemCatalog.get_item(id)
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
		return "Pockets full — could not add %s." % String(id)
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
			shop.stalk_market.price_today()
			for d: int in 7:
				week.append("%s %d" % [String(ClockService.WEEKDAYS[d]).substr(0, 3), shop.stalk_market.price_on(d)])
			return "Turnips (%s): %s" % [StalkMarket.Trend.keys()[shop.stalk_market.trend], ", ".join(week)]
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


## `place <visual id or furniture id> [x z]`: put a piece down in the room you are in, at the given
## cell or the first free one from (3, 3) — for looking at how a piece behaves.
func _cmd_place(args: PackedStringArray) -> String:
	var session: IndoorSession = Game.interior_session
	if session == null or session.room == null:
		return "Not in a room."
	if args.is_empty():
		return "Usage: place <visual id or furniture id> [x z]"
	var want := StringName(String(args[0]).to_lower())
	var data: FurnitureData = null
	for i: int in FurnitureCatalog.count():
		var candidate := ItemCatalog.get_item(FurnitureCatalog.item_id(i)) as FurnitureData
		if candidate != null and (candidate.id == want or candidate.visual_id == want):
			data = candidate
			break
	if data == null:
		return "No furniture '%s'." % want
	var cells: Array[Vector2i] = []
	if args.size() >= 3:
		cells.append(Vector2i(int(args[1]), int(args[2])))
	else:
		for z: int in range(2, session.room.rows - 1):
			for x: int in range(2, session.room.columns - 1):
				cells.append(Vector2i(x, z))
	for cell: Vector2i in cells:
		var entry: FurniturePlacement = session.place(data, cell, WorldGrid.Facing.SOUTH)
		if entry == null:
			continue
		var host: Interior = Interior.find(_tree())
		if host != null:
			host.spawn_placement(entry)
		return "Placed %s at %s." % [data.visual_id, cell]
	return "No room for %s." % data.visual_id


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
				return "Cockroaches waiting: %d (last played %d days ago)." % [house.roach_count, HouseCockroaches.days_away(house)]
			house.roach_count = HouseCockroaches.clamp_count(int(args[1]))
			return "%d cockroaches are waiting in the walls." % house.roach_count
		"neglect":
			var days: int = int(args[1]) if args.size() >= 2 and String(args[1]).is_valid_int() else 10
			var then: Dictionary = Time.get_datetime_dict_from_unix_time(
				int(Time.get_unix_time_from_datetime_dict({"year": Clock.year, "month": Clock.month, "day": Clock.day, "hour": 12})) - days * 86400
			)
			house.roach_year = int(then["year"])
			house.roach_month = int(then["month"])
			house.roach_day = int(then["day"])
			HouseCockroaches.decide_family_count(house)
			return "Away %d days: %d cockroaches waiting." % [days, house.roach_count]
		"statue":
			if args.size() >= 2 and String(args[1]).to_lower() == "built":
				house.next_size_tier = House.SizeTier.STATUE
				house.statue_rank = clampi(int(args[2]), 0, 3) if args.size() >= 3 else 0
				var tree := _tree()
				if tree != null:
					for node: Node in tree.get_nodes_in_group(Statue.GROUP):
						(node as Statue).refresh()
				return "The statue stands by the station (rank %d)." % house.statue_rank
			house.size_tier = House.SizeTier.UPPER
			house.next_size_tier = House.SizeTier.UPPER
			Game.inventory.set_loan(0)
			return "House is at its final size with no loan. Talk to Tom Nook about the statue."
		"roof":
			house.outlook_pal = clampi(int(args[1]), 0, PlayerHouse.ROOF_LETTERS.length() - 1) if args.size() >= 2 else 0
			house.next_outlook_pal = house.outlook_pal
			house.ordered_outlook_pal = house.outlook_pal
			var roof_tree := _tree()
			if roof_tree != null:
				var plot: Node = roof_tree.root.find_child(String(PlayerHouse.owned_building_id()), true, false)
				if plot != null and plot.has_method("refresh_seasonal_visual"):
					plot.call("refresh_seasonal_visual")
			return "Roof colour %d." % house.outlook_pal
		_:
			return "Usage: house [size|basement|build|loan|statue|roof N]"


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


## The word being typed at the end of a console line: its text, its position (0 = the
## command), the words before it, and the line up to it (`/` kept) for rewriting.
class Token:
	var text: String = ""
	var index: int = 0
	var prior := PackedStringArray()
	var prefix: String = ""

	func _init(p_text: String, p_index: int, p_prior: PackedStringArray, p_prefix: String) -> void:
		text = p_text
		index = p_index
		prior = p_prior
		prefix = p_prefix


func _token_at_end(line: String) -> Token:
	## Strip a leading `/` for command matching but keep spacing for rewrite.
	var working: String = line
	var slash: bool = working.begins_with("/")
	if slash:
		working = working.substr(1)
	var parts: PackedStringArray = working.split(" ", false)
	var ends_space: bool = line.ends_with(" ")
	if working.strip_edges().is_empty():
		return Token.new("", 0, PackedStringArray(), "/" if slash else "")
	if ends_space:
		return Token.new("", parts.size(), parts, line)
	var token: String = String(parts[parts.size() - 1])
	var prior: PackedStringArray = parts.slice(0, parts.size() - 1)
	var prefix: String = line.substr(0, line.length() - token.length())
	return Token.new(token, prior.size(), prior, prefix)


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


# --- Commands -------------------------------------------------------------------------------


## Give a tool and hold it (`equip red_pinwheel`).
func _cmd_equip(args: PackedStringArray) -> String:
	var msg: String = _cmd_give(args)
	var id := StringName(String(args[0]).to_lower()) if not args.is_empty() else &""
	for i: int in Inventory.POCKET_SLOTS:
		var slot: InventorySlot = Game.inventory.slot_at(i)
		if slot != null and not slot.is_empty() and slot.item.item_id == id:
			return "%s Equipped: %s." % [msg, Game.inventory.equip_slot(i)]
	return msg


## `bridge` sends Tortimer to the river for the second bridge; `bridge build` puts it
## up now in the first river acre with a spot.
func _cmd_bridge(args: PackedStringArray) -> String:
	var tree := _tree()
	var world: World = World.find(tree) if tree != null else null
	if world == null:
		return "No field here."
	if not args.is_empty() and String(args[0]) == "build":
		var blocks: Array[Vector2i] = SecondBridge.blocks(world.layout)
		if blocks.is_empty():
			return "No bridge spot in this town."
		var today: int = EventDates.ordinal(Clock.year, Clock.month, Clock.day)
		SecondBridge.order(blocks[blocks.size() - 1], today - 1)
		SecondBridge.build_if_due(today, Clock.hour)
		SecondBridge.restore(world, world.layout, world.grid)
		return "Bridge built in acre %s." % blocks[blocks.size() - 1]
	SecondBridge.note_day(EventDates.ordinal(Clock.year, Clock.month, Clock.day))
	Game.events.force(&"soncho_bridge_make")
	_sync_events()
	return "Tortimer is by the river (%d acres with a bridge spot)." % SecondBridge.blocks(world.layout).size()


## Lay an item on the unit in front of the player (`drop turnips_10`), as dropping does.
func _cmd_drop(args: PackedStringArray) -> String:
	var tree := _tree()
	var world: Node = World.find(tree) if tree != null else null
	var player: Node3D = Player.find(tree) if tree != null else null
	if world == null or player == null or args.is_empty():
		return "Usage: drop <item_id> (outdoors)."
	var ctx := InteractionContext.new()
	ctx.actor = player
	ctx.world = world
	var grid: WorldGrid = WorldGrid.of(world)
	var front: Vector2i = ToolUse.facing_cell(ctx)
	var cell: Vector2i = FieldItems.drop_cell(grid, front, front - grid.world_to_cell(player.global_position))
	if cell.x < 0 or FieldItems.put(world, cell, StringName(String(args[0]).to_lower())) == null:
		return "Can't drop here."
	return "Dropped %s at %s." % [args[0], cell]


## The shovel bouncing off something hard: the step back and the impact stars.
func _cmd_reflect(_args: PackedStringArray) -> String:
	var tree := _tree()
	var player := tree.get_first_node_in_group(Player.GROUP) as Player if tree != null else null
	if player == null:
		return "No player in this scene."
	var ctx := InteractionContext.new()
	ctx.actor = player
	ctx.world = World.find(tree)
	ToolUse._reflect_scoop_fx(ctx)
	return "Bounced."


## Walk up to a tree with December lights (Dec 10–25).
func _cmd_xmas(_args: PackedStringArray) -> String:
	var xm_tree := _tree()
	var xm_player := xm_tree.get_first_node_in_group(Player.GROUP) as Player if xm_tree != null else null
	if xm_player == null:
		return "No player in this scene."
	for xm_node: Node in xm_tree.get_nodes_in_group("plant"):
		if xm_node.find_child("XmasLights", true, false) != null:
			var xm_pos: Vector3 = (xm_node as Node3D).global_position
			xm_player.global_position = xm_pos + Vector3(0.0, 0.0, 2.5)
			return "Lit tree at %s." % xm_pos
	return "No lit trees."


## Bring the town's ball in front of the player (`ball`), or kick it (`ball kick`).
func _cmd_ball(args: PackedStringArray) -> String:
	var tree := _tree()
	var player := tree.get_first_node_in_group(Player.GROUP) as Player if tree != null else null
	var ball: FieldBall = FieldBall.find(tree)
	if player == null or ball == null:
		return "No ball here."
	var yaw: float = player.facing_yaw()
	if not args.is_empty() and String(args[0]) == "kick":
		ball.kick(Vector2(sin(yaw), cos(yaw)), Vector2(sin(yaw), cos(yaw)) * 7.5 * FieldBall.FRAME)
		return "Kicked."
	ball.in_hole = false
	ball.dead = false
	ball.global_position = player.global_position + Vector3(sin(yaw), 0.0, cos(yaw)) * 2.0
	ball.snap_ground()
	return "Ball at %s." % ball.global_position


## Play the dig-up report for an item (`digup conch`), or the loan cheer (`digup paid`).
func _cmd_digup(args: PackedStringArray) -> String:
	var tree := _tree()
	var player := tree.get_first_node_in_group(Player.GROUP) as Player if tree != null else null
	if player == null:
		return "No player in this scene."
	if not args.is_empty() and String(args[0]) == "paid":
		Game.session.complete_payment = Game.PAYMENT_HOUSE
		player.reports.run_complete_payment()
		return "Debt paid."
	var item := StringName(String(args[0]) if not args.is_empty() else "conch")
	player.reports.run_dig_get(item, true, Vector2i(-1, -1), null)
	return "Dug up %s." % item


## `throwfish [fish id]`: stand at the nearest bank facing the water and let a fish go.
func _cmd_throwfish(args: PackedStringArray) -> String:
	var tree := _tree()
	var player := Player.find(tree) if tree != null else null
	var world := World.find(tree) if tree != null else null
	if player == null or world == null:
		return "No field."
	var fish := ItemCatalog.get_item(StringName(str(args[0])) if args.size() >= 1 else &"crucian_carp") as FishData
	if fish == null:
		return "No such fish."
	var is_water := func(at: Vector3) -> bool:
		var attr: int = FieldCollision.unit_attr_at(world.layout, world.grid, at)
		return attr >= 0 and FieldCatalog.is_water_attr(attr)
	var cells: Array[Vector2i] = []
	for body: WaterBodies.Body in world.fish.bodies:
		cells.append_array(body.cells)
	var from: Vector2i = world.grid.world_to_cell(player.global_position)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.distance_squared_to(from) < b.distance_squared_to(from))
	for cell: Vector2i in cells.slice(0, 80):
		for dir: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var stand: Vector3 = world.grid.cell_to_world(cell - dir * 2)
			if is_water.call(stand):
				continue
			var yaw: float = atan2(float(dir.x), float(dir.y))
			var water: Variant = CreatureRelease.search_water(is_water, stand, yaw)
			if water == null:
				continue
			var ground: float = FieldCollision.ground_y_at(world.layout, world.grid, stand)
			stand.y = ground if FieldCollision.has_floor(ground) else player.global_position.y
			player.global_position = stand
			player.set_facing(yaw)
			var w: Vector3 = water as Vector3
			w.y = world.fish.surface_at(w)
			player.sequences.release_from_pocket(fish, w)
			return "Threw %s." % fish.display_name
	return "No bank found."


## Walk up to the player's own mailbox and check it, as the A button would.
func _cmd_mailbox(_args: PackedStringArray) -> String:
	var tree := _tree()
	var player := Player.find(tree) if tree != null else null
	if player == null:
		return "No player."
	for node: Node in tree.get_nodes_in_group("interactable"):
		if node.has_method("stand_spot") and bool(node.call("is_owned")):
			var box := node as Node3D
			player.global_position = box.global_position + Vector3(0.3, 0.0, 1.6)
			var ctx := InteractionContext.new()
			ctx.actor = player
			box.call("interact", Interaction.of(Interaction.READ, "Check mailbox"), ctx)
			return "Checking the mailbox."
	return "No mailbox."


## Tool effects in front of the player: `fx dig`, `fx fill`, `fx chips`, `fx splash 3`
## (an `eTM_CallEffect` arg), `fx net`, `fx soul`.
func _cmd_fx(args: PackedStringArray) -> String:
	var player := Player.find(_tree())
	if player == null:
		return "No player."
	var bg: Array = player._bg()
	var yaw: float = player.facing_yaw()
	var at: Vector3 = player.global_position + Vector3(sin(yaw), 0.0, cos(yaw)) * 2.0
	var attr: int = FootstepEffects.attr_at(bg, at)
	match String(args[0]) if not args.is_empty() else "dig":
		"dig":
			FootstepEffects.dig_sequence(bg, at, player, attr, false)
		"fill":
			for i: int in range(3, 6):
				FootstepEffects.dig_hole(bg, at, player.global_position, yaw, attr, i)
			FootstepEffects.dig_scoop(bg, at, player.global_position, yaw, attr, 2)
		"chips":
			FootstepEffects.axe_chips(bg, player.global_position, yaw)
		"splash":
			FootstepEffects.bobber_splash(at, int(args[1]) if args.size() > 1 else 3)
		"net":
			FootstepEffects.net_splash(bg, at, yaw)
		"soul":
			## A trodden roach's soul (`ef_goki`).
			FieldEffects.spawn(player.get_parent(), FieldEffects.Kind.ROACH, at, 0.0)
		_:
			return "fx dig | fill | chips | splash N | net | soul"
	return "Spawned."


## The umbrella twirl's spray at the player (`ef_kasamizu`; drops only in rain).
func _cmd_twirl(_args: PackedStringArray) -> String:
	var player := Player.find(_tree())
	if player == null:
		return "No player."
	FootstepEffects.umbrella_spray(player.global_position, player.facing_yaw())
	return "Twirled."


## The New Year's visit at the wishing well, coin and all (no question asked).
func _cmd_wish(args: PackedStringArray) -> String:
	var ws_tree := _tree()
	var ws_player := Player.find(ws_tree)
	var ws_well: WishingWell = WishingWell.find(ws_tree)
	if ws_player == null or ws_well == null:
		return "No well."
	if not args.is_empty() and args[0] == "queue":
		## `wish queue`: the villager at the front of a column lets the player in, as if
		## they'd said Yes (`aHN0_talk_saisen_suru`).
		var ws_queue: ShrineQueue = ShrineQueue.find(ws_tree)
		for ws_v: Node in ws_tree.get_nodes_in_group("event_npc"):
			if ws_queue != null and ws_v.get("_well") != null and int(ws_v.get("_sq_state")) == 1 \
					and ws_queue.can_offer(int(ws_v.get("slot"))):
				ws_player.global_position = (ws_v as Node3D).global_position + Vector3(0.0, 0.0, 1.2)
				ws_queue.queue_player(int(ws_v.get("slot")))
				ws_v.set("_sq_let_in", true)
				return "Queued behind slot %d." % int(ws_v.get("slot"))
		return "Nobody at the front."
	var ws_stand: Array = ws_well.visit_stand()
	var ws_at: Vector3 = ws_stand[0]
	ws_player.global_position = ws_at
	ws_player.sequences.shrine_visit(ws_at, float(ws_stand[1]), true, ws_well.global_position.y)
	return "Wishing."


## `feel <happy|angry|sad|sleepy|normal>`: the villager nearest the camera falls into
## that mood for an hour (`mNpc_FEEL_*`).
func _cmd_feel(args: PackedStringArray) -> String:
	var tree := _tree()
	var cam: Camera3D = tree.root.get_viewport().get_camera_3d() if tree != null else null
	var names: PackedStringArray = ["normal", "happy", "angry", "sad", "sleepy"]
	if cam == null or args.is_empty() or not names.has(args[0]):
		return "Usage: feel <normal|happy|angry|sad|sleepy>"
	var best: Node3D = null
	for v: Node in tree.get_nodes_in_group("villagers"):
		if not (v is Node3D and v.get("state") != null and (v as Node3D).is_visible_in_tree()):
			continue
		var d: float = (v as Node3D).global_position.distance_to(cam.global_position)
		if best == null or d < best.global_position.distance_to(cam.global_position):
			best = v as Node3D
	if best == null:
		return "No villager."
	(best.get("state") as VillagerState).set_feel(names.find(args[0]), 60)
	return "%s feels %s." % [best.name, args[0]]


## `cam <closer|farther|left|right>`: step the indoor camera index as C-stick would.
func _cmd_cam(args: PackedStringArray) -> String:
	var tree := _tree()
	var node := tree.root.get_viewport().get_camera_3d() as FollowCamera if tree != null else null
	if node == null:
		return "No follow camera."
	var steps := {"closer": Vector2i(-1, 0), "farther": Vector2i(1, 0), "left": Vector2i(0, -1), "right": Vector2i(0, 1)}
	if args.is_empty() or not steps.has(String(args[0])):
		return "Usage: cam <closer|farther|left|right>"
	var step: Vector2i = steps[String(args[0])]
	node.step_indoor(step.x, step.y)
	return "Camera index %s." % [node.indoor_index()]


## `leave`: the villager nearest the camera pops back indoors and walks out of its
## door again (`aNPC_think_leave_house`).
func _cmd_leave(_args: PackedStringArray) -> String:
	var tree := _tree()
	var cam: Camera3D = tree.root.get_viewport().get_camera_3d() if tree != null else null
	if cam == null:
		return "No camera."
	var best: Villager = null
	for v: Node in tree.get_nodes_in_group("villagers"):
		if not (v is Villager) or (v as Villager).indoor_resident:
			continue
		var d: float = (v as Node3D).global_position.distance_to(cam.global_position)
		if best == null or d < best.global_position.distance_to(cam.global_position):
			best = v as Villager
	if best == null:
		return "No villager."
	best.replay_leave_home()
	return "%s leaves home." % best.name


## `manpu <clip|code>`: the villager nearest the camera reacts as if a talk line
## called for it.
func _cmd_manpu(args: PackedStringArray) -> String:
	var tree := _tree()
	var cam: Camera3D = tree.root.get_viewport().get_camera_3d() if tree != null else null
	if cam == null or args.is_empty():
		return "Usage: manpu <clip|code>"
	var best: Node3D = null
	for v: Node in tree.get_nodes_in_group("villagers"):
		if not (v is Node3D and v.get("conversation") != null and (v as Node3D).is_visible_in_tree()):
			continue
		var d: float = (v as Node3D).global_position.distance_to(cam.global_position)
		if best == null or d < best.global_position.distance_to(cam.global_position):
			best = v as Node3D
	if best == null:
		return "No villager."
	## Reactions only come in a talk: hold the villager still as a talk would.
	var ai: Variant = best.get("ai")
	if ai != null and not ai.is_talking():
		ai.begin_talk()
	(best.get("conversation") as VillagerConversation).cue_manpu(str(args[0]))
	return "%s: %s" % [best.name, NpcManpu.clip_for(str(args[0]))]


## Hold a seventh-stage axe one hit from breaking, and break it now (`BROKEN_AXE`).
func _cmd_axebreak(_args: PackedStringArray) -> String:
	_cmd_give(["axe_use_7"])
	for i: int in Inventory.POCKET_SLOTS:
		var slot: InventorySlot = Game.inventory.slot_at(i)
		if slot != null and not slot.is_empty() and slot.item.item_id == &"axe_use_7":
			Game.inventory.equip_slot(i)
	Game.session.axe_damage = AxeWear.LIMIT - 1
	var tree := _tree()
	var player: Player = Player.find(tree) if tree != null else null
	if player != null and AxeWear.apply(Game.inventory, false, player) == &"":
		player.reports.broken_axe()
		return "The axe broke."
	return "Axe at stage 7, one swing from breaking."


## Watch something drift off up and to the left, as after letting a bug go.
func _cmd_release(args: PackedStringArray) -> String:
	var tree := _tree()
	var player := Player.find(tree) if tree != null else null
	if player == null:
		return "No player."
	## Parented to the player so it keeps its offset wherever the player is put.
	var mark := Node3D.new()
	player.add_child(mark)
	var yaw: float = player.facing_yaw()
	## `release [turn° [height m]]`: where the thing goes, from the player's facing.
	var turn: float = deg_to_rad(float(args[0]) if args.size() >= 1 else 50.0)
	var up: float = float(args[1]) if args.size() >= 2 else 3.0
	mark.position = Vector3(sin(yaw + turn), 0.0, cos(yaw + turn)) * 2.5 + Vector3(0.0, up, 0.0)
	player.sequences.watch_release(mark, HeldTool.find_skeleton(player._mesh))
	return "Watching."


## Show the waterfall rainbow now (`rainbow_opacity` 1), or `rainbow off`.
func _cmd_rainbow(args: PackedStringArray) -> String:
	var on: bool = args.is_empty() or String(args[0]).to_lower() != "off"
	Game.rainbow.opacity = 1.0 if on else 0.0
	return "Rainbow %s." % ("on" if on else "off")


## Open the town map (`mSM_OVL_MAP`) as the sight-map board does.
func _cmd_map(_args: PackedStringArray) -> String:
	var tree := _tree()
	var ui: MapOverlay = MapOverlay.find(tree)
	if ui == null:
		return "No map UI in this scene."
	ui.open(true)
	return "Map open."


## Open the catalog, optionally on page 0-8 (1 wallpaper, 2 carpet).
func _cmd_catalog(args: PackedStringArray) -> String:
	var tree := _tree()
	var clg: CatalogOverlay = CatalogOverlay.find(tree)
	if clg == null:
		return "No catalog UI in this scene."
	if args.size() >= 2 and String(args[1]).to_lower() == "fill":
		## Every wallpaper and carpet as if collected.
		for kind: String in ["wall", "carpet"]:
			for i: int in 67:
				var goods: StringName = FurnitureCatalog.goods_id(kind, i)
				if goods != &"":
					Game.catalog.record(goods)
	clg.open()
	if not args.is_empty() and String(args[0]).is_valid_int():
		clg.show_page(int(args[0]))
	return "Catalog open."


## Open the post office bank terminal (`mSM_OVL_BANK`).
func _cmd_abd(_args: PackedStringArray) -> String:
	var tree := _tree()
	var abd: BankOverlay = BankOverlay.find(tree)
	if abd == null:
		return "No bank UI in this scene."
	abd.open()
	return "Bank terminal open."


## Open the post office's loan screen (`mSM_OVL_REPAY`).
func _cmd_repay(_args: PackedStringArray) -> String:
	var tree := _tree()
	var rp: RepayOverlay = RepayOverlay.find(tree)
	if rp == null:
		return "No loan screen in this scene."
	rp.open()
	return "Loan screen open."


## Open the community board's posts (`mSM_OVL_NOTICE`).
func _cmd_board(_args: PackedStringArray) -> String:
	var tree := _tree()
	var ui: NoticeBoardOverlay = NoticeBoardOverlay.find(tree)
	if ui == null:
		return "No notice board UI in this scene."
	ui.open()
	return "%d posts on the board." % Game.notice_board.count()


## Bee sting: `sting` plays it, `sting off` / `sting on` sets the swollen face,
## `sting swarm` lets a swarm loose, `sting tree` hides a nest in the nearest tree.
func _cmd_sting(args: PackedStringArray) -> String:
	var sting_tree := _tree()
	var mode: String = String(args[0]).to_lower() if not args.is_empty() else ""
	if mode == "off" or mode == "on":
		Game.bees.set_swollen(mode == "on")
		return "Face %s." % ("swollen" if Game.bees.swollen else "normal")
	var who := sting_tree.get_first_node_in_group(Player.GROUP) as Player if sting_tree != null else null
	if who == null:
		return "No player in this scene."
	if mode == "swarm":
		BeeSwarm.spawn(who.get_parent(), who.global_position + Vector3(4.0, 2.5, 4.0), who)
		return "A swarm is after you."
	if mode == "mosquito":
		who.sequences.run_stung_mosquito()
		return "Itchy."
	if mode == "tree":
		## The nearest tree hides a nest: shake it for the startle and the chase.
		var tree: Node3D = null
		for node: Node in sting_tree.get_nodes_in_group("plant"):
			if node is Node3D and node.has_method("can_bump"):
				if tree == null or (node as Node3D).global_position.distance_to(who.global_position) < tree.global_position.distance_to(who.global_position):
					tree = node as Node3D
		if tree == null:
			return "No tree nearby."
		PlantGrowth.set_shake_content(tree.call("_persist"), TreeUse.Content.BEES)
		return "%s has a nest. Shake it." % tree.name
	PlayerSe.bee_sting(who)
	who.sequences.run_stung_bee()
	return "Ouch."


## The town assessment now (`mFAs_GetFieldRank_Condition`); `town perfect` also sets
## fifteen perfect days so the well's spirit can come.
func _cmd_town(args: PackedStringArray) -> String:
	var tree := _tree()
	var world := World.find(tree) if tree != null else null
	if world == null:
		return "The assessment needs the outdoor field."
	if not args.is_empty() and String(args[0]).to_lower() == "perfect":
		Game.town.perfect_streak = TownAssessment.PERFECT_STREAK_MAX
		Game.town.perfect_streak_day = Clock.day_number()
	var r: Dictionary = TownAssessment.rate(world)
	return "Rank %d (score %d: %d perfect, %d good acres); condition %d at %s; trees %d, flowers %d, weeds %d, trash %d; streak %d." % [
		int(r["rank"]), int(r["score"]), int(r["perfect"]), int(r["good"]), int(r["condition"]),
		r["block"], int(r["trees"]), int(r["flowers"]), int(r["weeds"]), int(r["dust"]), Game.town.perfect_streak,
	]
	return ""


## Where today's money rock is (`moneyrock new` picks another now).
func _cmd_moneyrock(args: PackedStringArray) -> String:
	var tree := _tree()
	var world := World.find(tree) if tree != null else null
	if world == null:
		return "The money rock needs the outdoor field."
	if not args.is_empty() and String(args[0]).to_lower() == "new":
		Game.town.money_rock = ""
		Game.town.money_rock_day = -1
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		MoneyRock.renew(world, rng, Clock.day_number())
	if Game.town.money_rock == "":
		return "No money rock today."
	var rocks: Dictionary = MoneyRock.field_rocks(world)
	return "Money rock: %s in acre %s." % [Game.town.money_rock, rocks.get(StringName(Game.town.money_rock), "?")]


## The house's feng shui now (`mHsRm_GetHuusuiRoom`) and Nook's tier odds from it.
func _cmd_fengshui(_args: PackedStringArray) -> String:
	Game.refresh_feng_shui()
	var cut: Vector2i = ShopGoods.tier_cutoffs(Game.session.goods_power)
	return "Money power %d, goods power %d (Nook: rare %d%%, uncommon %d%%)." % [
		Game.session.money_power, Game.session.goods_power, cut.x, cut.y - cut.x]
	return ""


## The Wisp's night: `wisp` brings him out, `wisp found` as if he had been found,
## `wisp spirits 5` puts spirits in the pockets.
func _cmd_wisp(args: PackedStringArray) -> String:
	var state: Dictionary = WispEvent.state()
	var sub: String = String(args[0]) if not args.is_empty() else ""
	if sub == "found":
		state["found"] = true
		state["active"] = true
		return "Wisp found; spirits in acres %s." % [state.get("acres", [])]
	if sub == "spirits":
		var n: int = clampi(int(args[1]) if args.size() > 1 else WispEvent.SPIRITS, 1, WispEvent.SPIRITS)
		var bug: ItemData = BugCatalog.get_by_type(WispEvent.TYPE_SPIRIT)
		if bug == null or Game.inventory.add(bug, n) != 0:
			return "No room for spirits."
		return "%d spirit(s) in the pockets." % n
	Game.events.ghost_tonight = true
	Game.events.force(&"ghost")
	_sync_events()
	return "The Wisp is out tonight."


## Blanca in town with a test face (a smile) from "Tester".
func _cmd_blanca(_args: PackedStringArray) -> String:
	var bl_face := MaskCat.blank_face()
	for bl_i: int in 32:
		bl_face.pixels[8 * 32 + bl_i] = 1
		bl_face.pixels[22 * 32 + bl_i] = 1
		bl_face.pixels[bl_i * 32 + 8] = 4
		bl_face.pixels[bl_i * 32 + 23] = 4
	MaskCat.store(bl_face, "Tester", EventDates.ordinal(Clock.year, Clock.month, Clock.day))
	Game.events.force(&"mask_npc")
	_sync_events()
	return "Blanca is in town."


## Hold up a golden tool (`golden net|rod|axe`), as after Tortimer's visit or the well.
func _cmd_golden(args: PackedStringArray) -> String:
	var ids: Dictionary = {"net": &"golden_net", "rod": &"golden_fishing_rod", "axe": &"golden_axe"}
	var id: StringName = ids.get(String(args[0]) if not args.is_empty() else "rod", &"golden_fishing_rod")
	var tree := _tree()
	var player := Player.find(tree) as Player if tree != null else null
	if player == null:
		return "No player here."
	player.reports.get_golden_item(id)
	return "Holding up %s." % id


## A villager buries something now and posts where (`mNtc_check_treasure`).
func _cmd_treasure(_args: PackedStringArray) -> String:
	var tree := _tree()
	var world: World = World.find(tree) if tree != null else null
	if world == null:
		return "No field here."
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var cell: Vector2i = BuriedTreasure.check(world, rng, true)
	if cell.x < 0:
		return "Nothing buried."
	var rec: Dictionary = BuriedUse.record(BuriedUse.persist_id(cell))
	return "%s buried at %s (acre %s): %s" % [rec.get("item_id", "?"), cell,
		VillagerWalk.block_from_cell(cell), str(Game.notice_board.posts[-1]["text"]).replace("\n", " ")]
	return ""


## The calendar (`calendar day 31` opens on a day); `calendar played 2026-9-14` /
## `calendar tortimer 2026-9-14` mark a day.
func _cmd_calendar(args: PackedStringArray) -> String:
	var tree := _tree()
	if args.size() > 1 and String(args[0]) == "day":
		var day_ui: CalendarOverlay = CalendarOverlay.find(tree)
		if day_ui == null:
			return "No calendar here."
		day_ui.open_on_day(int(args[1]))
		return "Calendar on day %s." % args[1]
	if args.size() > 1:
		var d: PackedStringArray = String(args[1]).split("-")
		if d.size() != 3:
			return "Date as Y-M-D."
		var n: int = EventDates.ordinal(int(d[0]), int(d[1]), int(d[2]))
		var today: int = EventDates.ordinal(Clock.year, Clock.month, Clock.day)
		CalendarBook.trim(Game.resident.calendar, today)
		var key: String = "events" if String(args[0]) == "tortimer" else "played"
		if not (Game.resident.calendar[key] as Array).has(n):
			(Game.resident.calendar[key] as Array).append(n)
		return "Marked %s as %s." % [args[1], key]
	var ui: CalendarOverlay = CalendarOverlay.find(tree)
	if ui == null:
		return "No calendar here."
	ui.open()
	return "Calendar."


## Mom writes now: today's dated letter if there is one, else an everyday letter
## (`mom 0x151` for a given one).
func _cmd_mom(args: PackedStringArray) -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pick: Dictionary = MotherMail.dated(Clock.month, Clock.day, VillagerTalkManager.birthday(),
		MotherMail.holiday(Clock.year, Clock.month, Clock.day), rng)
	if not args.is_empty():
		var no: int = String(args[0]).hex_to_int() if String(args[0]).begins_with("0x") else int(args[0])
		var idx: int = no - MotherMail.MSG_NORMAL
		pick = {"msg": no, "present": MotherMail.normal_present(idx, rng) if idx >= 0 and idx < MotherMail.NORMAL_COUNT else &""}
	elif pick.is_empty():
		var left: Array[int] = MotherMail.normal_left(Game.resident.mother_mail)
		var n: int = left[rng.randi_range(0, left.size() - 1)] if not left.is_empty() else 0
		pick = {"msg": MotherMail.MSG_NORMAL + n, "present": MotherMail.normal_present(n, rng)}
	var mail: MailData = MotherMail.letter(int(pick["msg"]), StringName(pick["present"]),
		MotherMail.paper(Clock.month, Clock.day, VillagerTalkManager.birthday()), Game.resident.player_name)
	if mail == null or not MailDelivery.to_mailbox(mail):
		return "Mom couldn't write (no mail bank or the mailbox is full)."
	var tree := _tree()
	var reader: LetterReaderOverlay = LetterReaderOverlay.find(tree)
	if reader != null:
		reader.open(mail)
	return "Letter 0x%X from Mom in the mailbox%s." % [int(pick["msg"]),
		(" with %s" % mail.present_item_id) if mail.present_item_id != &"" else ""]
	return ""


## `birthday` opens the "When's your birthday?" picker; `birthday visit [rod|net]`
## sends the present visitor to the player now; `birthday cards` mails the cards.
func _cmd_birthday(args: PackedStringArray) -> String:
	var tree := _tree()
	var sub: String = String(args[0]).to_lower() if not args.is_empty() else ""
	if sub == "cards":
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var sent: int = PresentVisit.send_cards(Game.residents, Game.relationships, &"",
			Game.resident.player_name, rng, MailDelivery.to_mailbox)
		return "%d birthday card(s) sent." % sent
	if sub == "visit":
		var kind: int = PresentVisit.Kind.BIRTHDAY
		if args.size() > 1:
			kind = PresentVisit.Kind.GOLDEN_NET if String(args[1]) == "net" else PresentVisit.Kind.GOLDEN_ROD
		else:
			Game.resident.birthday_present_npc = PresentVisit.birthday_npc(Game.residents, Game.relationships)
			if Game.resident.birthday_present_npc == &"" and not Game.residents.resident_ids().is_empty():
				Game.resident.birthday_present_npc = Game.residents.resident_ids()[0]
		var player: Player = Player.find(tree) if tree != null else null
		var world: Node = World.find(tree) if tree != null else null
		if player == null or world == null:
			return "No field here."
		var yaw: float = player.facing_yaw()
		var npc: Node3D = load("res://features/events/present_npc.gd").spawn(
			world.get_node("Characters"), kind, player.global_position, yaw)
		return "Present visit." if npc != null else "Nobody to send."
	var ui: BirthdayOverlay = BirthdayOverlay.find(tree)
	if ui == null:
		return "No birthday screen here."
	ui.open()
	return "Birthday: pick a date."


## Open the diary on a month (`diary 4`), or write a line into one first
## (`diary 4 Went fishing all day.`).
func _cmd_diary(args: PackedStringArray) -> String:
	var tree := _tree()
	var ui: DiaryOverlay = DiaryOverlay.find(tree)
	if ui == null:
		return "No diary screen here."
	var month: int = clampi(int(args[0]), 1, 12) if not args.is_empty() and String(args[0]).is_valid_int() else Clock.month
	if args.size() > 1:
		Game.resident.diary[month] = DiaryOverlay.clip(" ".join(args.slice(1)))
	ui.open(month)
	return "Diary: month %d." % month


## Set the sunburn rank 0–8 (`mPr_sunburn_c`) and repaint the face.
func _cmd_tan(args: PackedStringArray) -> String:
	if args.is_empty() or not String(args[0]).is_valid_int():
		return "Tan rank %d (hold %d days)." % [int(Game.resident.sunburn.get("rank", 0)), int(Game.resident.sunburn.get("hold", 0))]
	Game.resident.sunburn["rank"] = clampi(int(args[0]), 0, Sunburn.MAX_RANK)
	Game.resident.sunburn["changed"] = Clock.day_number()
	Game.resident.sunburn["hold"] = Sunburn.HOLD_DAYS if int(Game.resident.sunburn["rank"]) > 0 else 0
	Game.bees.face_changed.emit()
	return "Tan rank %d." % int(Game.resident.sunburn["rank"])


## The body and head balls a few units ahead of the player, at size 0–1
## (`snowballs 0.5`; default 0.4, big enough to push).
func _cmd_snowballs(args: PackedStringArray) -> String:
	var sb_tree := _tree()
	var sb_world := World.find(sb_tree) if sb_tree != null else null
	var sb_player := Player.find(sb_tree) if sb_tree != null else null
	if sb_world == null or sb_player == null:
		return "Snowballs need the outdoor field."
	var sb_collide: bool = not args.is_empty() and String(args[0]).to_lower() == "collide"
	var sb_args: PackedStringArray = args.slice(1) if sb_collide else args
	var sb_n: float = clampf(float(sb_args[0]), 0.0, 1.0) if not sb_args.is_empty() and String(sb_args[0]).is_valid_float() else 0.4
	var sb_cell: Vector2i = sb_world.grid.world_to_cell(sb_player.global_position)
	var sb_fwd := Vector3(sin(sb_player.facing_yaw()), 0.0, cos(sb_player.facing_yaw()))
	var sb_dir := Vector2i(roundi(sb_fwd.x), roundi(sb_fwd.z))
	if sb_dir == Vector2i.ZERO:
		sb_dir = Vector2i(0, 1)
	var sb_side := Vector2i(-sb_dir.y, sb_dir.x)
	SnowmanUse.spawn_ball(sb_world, SnowmanRules.PART_BODY, sb_cell + sb_dir * 2, sb_n * SnowmanRules.MOVE_DIST_MAX)
	## `snowballs collide`: the head starts against the body, rolling into it.
	var sb_gap: int = 1 if sb_collide else 3
	var sb_head: Snowball = SnowmanUse.spawn_ball(sb_world, SnowmanRules.PART_HEAD, sb_cell + sb_dir * 2 + sb_side * sb_gap, sb_n * 0.85 * SnowmanRules.MOVE_DIST_MAX)
	if sb_collide and sb_head != null:
		sb_head.set("vel", Vector2(-sb_side.x, -sb_side.y) * 1.0)
	return "Two snowballs at size %.2f%s." % [sb_n, ", the head rolling in" if sb_collide else ""]


## A finished snowman two units ahead (`snowman [score 0-3]`).
func _cmd_snowman(args: PackedStringArray) -> String:
	var tree := _tree()
	var world := World.find(tree) if tree != null else null
	var player := Player.find(tree) if tree != null else null
	if world == null or player == null:
		return "A snowman needs the outdoor field."
	var score: int = clampi(int(args[0]), 0, 3) if not args.is_empty() and String(args[0]).is_valid_int() else 0
	var fwd := Vector3(sin(player.facing_yaw()), 0.0, cos(player.facing_yaw()))
	var cell: Vector2i = SnowmanUse.fg_cell(world, world.grid.world_to_cell(player.global_position + fwd * 4.0))
	if cell.x < 0:
		return "No room for a snowman there."
	var slot: int = SnowmanRules.free_slot(Game.town.snowmen)
	if slot >= 0:
		Game.town.snowmen[slot] = {"head": 0.6, "body": 0.7, "score": score, "cell": [cell.x, cell.y], "age": 0}
	SnowmanUse.spawn_snowman(world, slot, cell, 0.6, 0.7, score)
	return "Snowman (score %d) in slot %d." % [score, slot]


## Set N mushrooms under trees now (`mMsr_SetMushroomNum`), or `mushrooms clear`.
func _cmd_mushrooms(args: PackedStringArray) -> String:
	var tree := _tree()
	var world := World.find(tree) if tree != null else null
	if world == null:
		return "Mushrooms need the outdoor field."
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	if not args.is_empty() and String(args[0]).to_lower() == "clear":
		MushroomUse.clear(world, Game.town.mushrooms.size(), Vector2i(-1, -1), rng)
		return "Mushrooms cleared."
	var n: int = int(args[0]) if not args.is_empty() and String(args[0]).is_valid_int() else MushroomUse.NUM
	var set: int = MushroomUse.grow(world, n, Vector2i(-1, -1), rng)
	return "%d mushrooms set (%d in town)." % [set, Game.town.mushrooms.size()]


## Put up a signboard in front of the player, showing design slot N if given.
func _cmd_signboard(args: PackedStringArray) -> String:
	var tree := _tree()
	var world := World.find(tree) if tree != null else null
	var player: Node3D = Player.find(tree) if tree != null else null
	if world == null or player == null:
		return "Signboards need the outdoor field."
	var ctx := InteractionContext.new()
	ctx.world = world
	ctx.actor = player
	var cell: Vector2i = ToolUse.facing_cell(ctx)
	if not SignboardUse.place(world, cell):
		return "Can't put a signboard there."
	if not args.is_empty() and String(args[0]).is_valid_int():
		SignboardUse.post(SignboardUse.persist_id(cell), Game.designs.player[clampi(int(args[0]), 0, 7)])
		for n: Node in tree.get_nodes_in_group(SignboardUse.GROUP):
			n.call("refresh_design")
	return "Signboard up at %s." % cell


## Send a shooting star across the pond now (Meteor Shower only, `ef_shooting`).
func _cmd_meteor(_args: PackedStringArray) -> String:
	var tree := _tree()
	var node: Node = tree.get_first_node_in_group(MeteorShower.GROUP) if tree != null else null
	if node == null:
		return "No meteor shower tonight (event meteor_shower)."
	(node as MeteorShower).launch_now()
	return "Shooting star."


## Wash N shells up on the beach now (`mFI_SetShellWave`), with free wave units per acre.
func _cmd_shells(args: PackedStringArray) -> String:
	var tree := _tree()
	var world := World.find(tree) if tree != null else null
	if world == null:
		return "Shells need the outdoor field."
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var n: int = int(args[0]) if not args.is_empty() and String(args[0]).is_valid_int() else ShellUse.FIRST_NUM
	var free: Array[String] = []
	for b: Vector2i in ShellUse.beach_blocks():
		free.append("%d,%d:%d" % [b.x, b.y, ShellUse.free_cells(world, world.grid, b).size()])
	var set: int = ShellUse.wash_up(world, n, Vector2i(-1, -1), rng)
	return "%d shells set (%d on the beach; free %s)." % [set, Game.town.shells.size(), " ".join(free)]


## Sow N weeds now (`mAGrw_SetGrass`), or `weeds clear`.
func _cmd_weeds(args: PackedStringArray) -> String:
	var tree := _tree()
	var world := World.find(tree) if tree != null else null
	if world == null:
		return "Weeds need the outdoor field."
	if not args.is_empty() and String(args[0]).to_lower() == "clear":
		WeedUse.clear_all(world, world.grid)
		return "Weeds cleared."
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var n: int = int(args[0]) if not args.is_empty() and String(args[0]).is_valid_int() else WeedUse.PER_DAY
	var grown: int = WeedUse.grow(world, world.grid, world.layout, n, rng)
	return "%d weeds sown (%d in town)." % [grown, WeedUse.count()]


## Play radio exercise move 0-17 (`mPlayer_RADIO_EXERCISE_CMD*`).
func _cmd_exercise(args: PackedStringArray) -> String:
	var tree := _tree()
	var player := tree.get_first_node_in_group(Player.GROUP) as Player if tree != null else null
	if player == null:
		return "No player in this scene."
	var cmd: int = int(args[0]) if not args.is_empty() and String(args[0]).is_valid_int() else 0
	player.sequences.run_radio_exercise(cmd)
	return "Exercise %d." % cmd


## Bury a pitfall under the player; `pitfall auto` also struggles for you.
func _cmd_pitfall(args: PackedStringArray) -> String:
	var tree := _tree()
	var player := tree.get_first_node_in_group(Player.GROUP) as Player if tree != null else null
	var world := World.find(tree) if tree != null else null
	if player == null or world == null:
		return "Pitfalls need the outdoor field."
	var ctx := InteractionContext.new()
	ctx.world = world
	ctx.actor = player
	var at: Vector3 = player.global_position
	if not args.is_empty() and String(args[0]).to_lower() == "villager":
		var best: Node3D = null
		for v: Node in tree.get_nodes_in_group("villagers"):
			var v3 := v as Node3D
			if v3 != null and v3.is_visible_in_tree() and (best == null or v3.global_position.distance_to(at) < best.global_position.distance_to(at)):
				best = v3
		if best == null:
			return "No villager nearby."
		at = best.global_position
	var cell: Vector2i = world.grid.world_to_cell(at)
	if not HoleUse.dig(ctx, cell, false) or not BuriedUse.bury(ctx, cell, BuriedUse.PITFALL_ITEM):
		return "Can't bury a pitfall here."
	if not args.is_empty() and String(args[0]).to_lower() == "auto":
		player.struggle_assist = 0.1
	return "Pitfall buried at %s." % cell


## `island [home]`: swap to Kapp'n's island (or back to the town) without the boat.
func _cmd_island(args: PackedStringArray) -> String:
	Game.island_visit = args.is_empty() or String(args[0]) != "home"
	Game.island_ride = &""
	Game.travel_to_world()
	return "Island." if Game.island_visit else "Town."


## Take Kapp'n's boat now, as if the talk had ended on yes.
func _cmd_ride(args: PackedStringArray) -> String:
	var tree := _tree()
	var service: IslandService = tree.root.find_child("IslandService", true, false) as IslandService
	if service == null:
		return "No boat here."
	var talk := KappnTalk.new()
	talk.ride = true
	service.mute = not args.is_empty() and String(args[0]) == "fast"
	service._on_talked(talk)
	return "All aboard."


## The cannon furniture's shell, fired away from the camera over the player's ground.
func _cmd_cannon(_args: PackedStringArray) -> String:
	var player: Node3D = Player.find(_tree())
	if player == null:
		return "No player."
	var at: Vector3 = player.global_position + Vector3(0.0, 0.8, 0.0)
	CannonShot.fire(player.get_parent(), at, 0.0, Rect2(at.x - 30.0, at.z - 30.0, 60.0, 60.0))
	return "Bang."


## A New Year's party popper going off beside the player (`eEC_EFFECT_CLACKER`).
func _cmd_popper(_args: PackedStringArray) -> String:
	var player: Node3D = Player.find(_tree())
	if player == null:
		return "No player."
	PartyPopper.fire(player.get_parent(), player.global_position + Vector3(0.0, 0.6, 1.0))
	return "Pop."


## A washed car glittering where the player stands (`eEC_EFFECT_CAR_BLIGHT`).
func _cmd_shine(_args: PackedStringArray) -> String:
	var player: Node3D = Player.find(_tree())
	if player == null:
		return "No player."
	CarBlight.start(player.get_parent(), player.global_position + Vector3(0.0, 0.0, 1.0), true)
	return "Glitter."


## The puff after a trick changes the player's clothes (`eEC_EFFECT_HALLOWEEN`).
func _cmd_costume(_args: PackedStringArray) -> String:
	return "Puff." if CostumePuff.at_player() != null else "No player."


## `glow [vanish]`: the well spirit's glow in front of the player (`eEC_EFFECT_MAKE_HEM`).
func _cmd_glow(args: PackedStringArray) -> String:
	var player: Node3D = Player.find(_tree())
	if player == null:
		return "No player."
	var vanish: bool = not args.is_empty() and String(args[0]) == "vanish"
	var feet: Vector3 = player.global_position + Vector3(0.0, 0.0, 2.0)
	SpiritGlow.play(player.get_parent(), feet, not vanish)
	var light: SpiritLight = SpiritLight.start(player.get_parent(), feet)
	if vanish:
		light.finish()
	return "Glow."


func _cmd_clear(_args: PackedStringArray) -> String:
	return "__clear__"
