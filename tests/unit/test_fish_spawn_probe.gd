extends GdUnitTestSuite

## Exploratory: run the real `FishSchool` spawn loop (not `spawn()` directly) across
## months and water kinds and print what actually turns up. Kept as a smoke test that
## every water body stocks itself with in-season, in-ceiling species.

const STEP := 1.0 / 60.0


func before_test() -> void:
	Game.reset_session()
	FishCatalog.reload()
	FishSpawnScheduler.reload()
	Clock.reset_to_default()
	Clock.paused = true


func after_test() -> void:
	Clock.reset_to_default()
	Clock.paused = false


func _world(fill: Callable) -> Dictionary:
	var grid := WorldGrid.new()
	grid.configure(24, 24, 2.0, Vector3(-24, 0, -24))
	fill.call(grid)
	var school := FishSchool.new()
	school.configure(grid, 0.0)
	school.seed_rng(1)
	return {"grid": grid, "school": school}


func _run(school: FishSchool, grid: WorldGrid, player_cell: Vector2i, seconds: float) -> Dictionary:
	var seen: Dictionary = {}
	var sense := FishShadow.Sense.new()
	sense.player_position = grid.cell_to_world(player_cell)
	var elapsed: float = 0.0
	while elapsed < seconds:
		school.tick(STEP * 4.0, sense)
		for shadow: FishShadow in school.shadows:
			seen[String(shadow.fish.id)] = int(seen.get(String(shadow.fish.id), 0)) + 1
		elapsed += STEP * 4.0
	return seen


func test_river_stocks_seasonal_species() -> void:
	var w := _world(func(g: WorldGrid) -> void:
		for z: int in range(2, 22):
			for x: int in range(9, 13):
				g.set_terrain(Vector2i(x, z), WorldGrid.Terrain.WATER)
	)
	var school: FishSchool = w["school"]
	var body: WaterBodies.Body = school.bodies[0]
	assert_that(body.kind).is_equal(WaterBodies.Kind.RIVER)

	Clock.month = 1
	Clock.day = 10
	Clock.hour = 12
	var jan := _run(school, w["grid"], Vector2i(11, 11), 8.0)
	prints("JAN river:", jan)
	assert_bool(jan.size() > 0).override_failure_message("river stocked nothing in January").is_true()

	school.clear()
	Game.reset_session()
	Clock.month = 7
	var jul := _run(school, w["grid"], Vector2i(11, 11), 8.0)
	prints("JUL river:", jul)
	assert_bool(jul.size() > 0).is_true()
	## Nothing over the river's XL ceiling (no whale, no arapaima=XXL).
	for id: String in jul:
		var fish: FishData = FishCatalog.get_fish(StringName(id))
		assert_int(int(fish.size_class)).override_failure_message(
			"%s (size %d) spawned in a river" % [id, fish.size_class]
		).is_less_equal(int(FishData.SizeClass.XL))


func test_ocean_stocks_saltwater_species() -> void:
	var w := _world(func(g: WorldGrid) -> void:
		for z: int in range(0, 10):
			for x: int in range(0, 24):
				g.set_terrain(Vector2i(x, z), WorldGrid.Terrain.WATER)
	)
	var school: FishSchool = w["school"]
	assert_that(school.bodies[0].kind).is_equal(WaterBodies.Kind.OCEAN)

	Clock.month = 6
	Clock.day = 10
	Clock.hour = 12
	var seen := _run(school, w["grid"], Vector2i(12, 6), 10.0)
	prints("JUN ocean:", seen)
	assert_bool(seen.size() > 0).is_true()
	var saltwater := ["sea_bass", "red_snapper", "barred_knifejaw"]
	var any_salt := false
	for id: String in seen:
		if id in saltwater:
			any_salt = true
	assert_bool(any_salt).override_failure_message(
		"ocean produced no saltwater fish: %s" % [seen]
	).is_true()


func test_garden_pond_is_empty_in_winter_stocked_in_summer() -> void:
	var w := _world(func(g: WorldGrid) -> void:
		for z: int in range(10, 16):
			for x: int in range(10, 16):
				g.set_terrain(Vector2i(x, z), WorldGrid.Terrain.WATER)
	)
	var school: FishSchool = w["school"]
	assert_that(school.bodies[0].kind).is_equal(WaterBodies.Kind.POND)

	Clock.month = 1
	Clock.day = 10
	Clock.hour = 12
	var winter := _run(school, w["grid"], Vector2i(13, 13), 8.0)
	prints("JAN pond:", winter)
	assert_int(winter.size()).override_failure_message(
		"p_month is NULL Jan-Mar; pond should stay empty, got %s" % [winter]
	).is_equal(0)

	school.clear()
	Game.reset_session()
	Clock.month = 6
	var summer := _run(school, w["grid"], Vector2i(13, 13), 8.0)
	prints("JUN pond:", summer)
	assert_bool(summer.size() > 0).override_failure_message("pond stocked nothing in June").is_true()
	for id: String in summer:
		var fish: FishData = FishCatalog.get_fish(StringName(id))
		assert_int(int(fish.size_class)).override_failure_message(
			"%s too big for a 36-cell pond" % id
		).is_less_equal(int(FishData.SizeClass.L))
