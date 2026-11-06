class_name TestIslandBugs
extends GdUnitTestSuite

## `l_insect_island` (`aSOI_ins_make_insect_island_range_data`): the island's insects follow the
## hour only, from tables of their own.


func _types(entries: Array[BugSpawnEntry]) -> Array[int]:
	var out: Array[int] = []
	for e: BugSpawnEntry in entries:
		out.append(e.type_index)
	return out


func _weight_of(entries: Array[BugSpawnEntry], type_index: int) -> float:
	for e: BugSpawnEntry in entries:
		if e.type_index == type_index:
			return e.weight
	return 0.0


func test_every_hour_has_a_list() -> void:
	for hour: int in 24:
		assert_bool(BugSpawnTable.island_entries(hour).is_empty()).is_false()


func test_the_small_hours_are_beetles_and_a_snail() -> void:
	var entries: Array[BugSpawnEntry] = BugSpawnTable.island_entries(2)
	assert_int(entries.size()).is_equal(7)
	assert_float(_weight_of(entries, 19)).is_equal(6.0)  ## DRONE_BEETLE on a tree
	assert_float(_weight_of(entries, 32)).is_equal(3.0)  ## SNAIL when raining on a flower


func test_the_day_brings_butterflies_and_the_late_afternoon_evening_cicadas() -> void:
	var day: Array[BugSpawnEntry] = BugSpawnTable.island_entries(12)
	assert_int(day.size()).is_equal(16)
	assert_float(_weight_of(day, 2)).is_equal(10.0)  ## TIGER_BUTTERFLY
	assert_float(_weight_of(day, 6)).is_equal(0.0)  ## no evening cicada yet
	var late: Array[BugSpawnEntry] = BugSpawnTable.island_entries(16)
	assert_float(_weight_of(late, 6)).is_equal(27.0)  ## EVENING_CICADA


func test_the_island_list_is_the_same_whatever_the_month() -> void:
	## The town's lists change by month; the island's is not keyed by month at all.
	assert_array(_types(BugSpawnTable.island_entries(9))).is_equal(_types(BugSpawnTable.island_entries(10)))
	assert_array(_types(BugSpawnTable.island_entries(9))).is_not_equal(_types(BugSpawnTable.island_entries(2)))


func test_the_island_field_only_births_island_species() -> void:
	var town: WorldData = WorldGenerator.generate(12345)
	var layout: WorldData = WorldGenerator.generate_island(town)
	var grid := WorldGrid.new()
	grid.configure_from_world(layout)
	var allowed: Dictionary = {38: true, 28: true}  ## the always-on ants and cockroach
	for hour: int in [2, 12, 16, 22]:
		for e: BugSpawnEntry in BugSpawnTable.island_entries(hour):
			allowed[e.type_index] = true
	var was_island: bool = Game.island_visit
	Game.island_visit = true
	Clock.month = 7
	Clock.hour = 12
	var seen: int = 0
	var strays: Array[int] = []
	for seed_value: int in range(1, 41):
		var field := BugField.new()
		field.auto_spawn = true
		field.configure(grid, layout)
		field.seed_rng(seed_value)
		var sense := BugActor.Sense.new()
		sense.player_position = grid.cell_to_world(Vector2i(8, 8))
		sense.wade_end = grid.cell_to_world(Vector2i(8, 8))
		for _i: int in roundi(BugField.SET_WAIT * 60.0) + 1:
			field.advance(1.0 / 60.0, sense)
		for actor: BugActor in field.actors:
			seen += 1
			if not allowed.has(actor.bug.type_index):
				strays.append(actor.bug.type_index)
	Game.island_visit = was_island
	assert_int(seen).is_greater(0)
	assert_array(strays).is_empty()
