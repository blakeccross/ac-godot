class_name TestDebugConsole
extends GdUnitTestSuite


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true
	Game.reset_session()
	ItemCatalog.reload()


func after_test() -> void:
	Clock.reset_to_default()
	Clock.paused = false
	Game.reset_session()


func test_weather_command_sets_session() -> void:
	var console := DebugConsole.new()
	var msg: String = console.execute("weather rain heavy")
	assert_str(msg).contains("rain")
	assert_that(Game.weather).is_equal(&"rain")
	assert_int(Game.weather_intensity).is_equal(int(Weather.Intensity.HEAVY))


func test_season_command_jumps_to_boundary() -> void:
	var console := DebugConsole.new()
	Clock.apply_snapshot({"year": 2001, "month": 1, "day": 15, "hour": 8, "minute": 0})
	var msg: String = console.execute("season summer")
	assert_str(msg).contains("Summer")
	assert_that(Clock.season()).is_equal(ClockService.Season.SUMMER)
	assert_int(Clock.month).is_equal(5)
	assert_int(Clock.day).is_equal(26)
	assert_int(Clock.hour).is_equal(12)


func test_season_next_advances() -> void:
	var console := DebugConsole.new()
	Clock.apply_snapshot({"year": 2001, "month": 1, "day": 15, "hour": 8, "minute": 0})
	console.execute("season next")
	assert_that(Clock.season()).is_equal(ClockService.Season.SPRING)


func test_give_adds_item() -> void:
	var console := DebugConsole.new()
	Game.inventory.clear()
	var msg: String = console.execute("give apple 3")
	assert_str(msg).contains("3")
	assert_int(Game.inventory.count_of(&"apple")).is_equal(3)


func test_give_unknown_item() -> void:
	var console := DebugConsole.new()
	var msg: String = console.execute("give not_a_real_item")
	assert_str(msg).contains("Unknown item")


func test_time_set_and_advance() -> void:
	var console := DebugConsole.new()
	Clock.apply_snapshot({"year": 2001, "month": 3, "day": 1, "hour": 10, "minute": 0})
	console.execute("time 18:30")
	assert_int(Clock.hour).is_equal(18)
	assert_int(Clock.minute).is_equal(30)
	console.execute("time +1h")
	assert_int(Clock.hour).is_equal(19)


func test_bells_sets_wallet() -> void:
	var console := DebugConsole.new()
	console.execute("bells 5000")
	assert_int(Game.inventory.wallet).is_equal(5000)


func test_slash_prefix_stripped() -> void:
	var console := DebugConsole.new()
	console.execute("/weather snow")
	assert_that(Game.weather).is_equal(&"snow")


func test_autocomplete_commands() -> void:
	var console := DebugConsole.new()
	var matches: PackedStringArray = console.suggestions("wea")
	assert_that(matches).contains("weather")
	assert_str(console.autocomplete("wea")).is_equal("weather ")


func test_autocomplete_weather_kinds() -> void:
	var console := DebugConsole.new()
	var matches: PackedStringArray = console.suggestions("weather ra")
	assert_that(matches).contains("rain")
	assert_str(console.autocomplete("weather ra")).is_equal("weather rain ")


func test_autocomplete_give_items() -> void:
	var console := DebugConsole.new()
	var matches: PackedStringArray = console.suggestions("give app")
	assert_that(matches).contains("apple")
	var filled: String = console.autocomplete("give app")
	assert_str(filled).starts_with("give app")


func test_unknown_command() -> void:
	var console := DebugConsole.new()
	var msg: String = console.execute("fly")
	assert_str(msg).contains("Unknown command")
