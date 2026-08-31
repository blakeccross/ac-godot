class_name TestFishShadow
extends GdUnitTestSuite

## Visible fish: the size tables from `ac_gyo_test.c`, the water bodies they swim in, and
## the `aGTT_*` action machine. Timing-sensitive behaviour is driven in 60 Hz steps because
## the decomp tables are frame counts.

const STEP := 1.0 / 60.0

var _grid: WorldGrid = null
var _pond: WaterBodies.Body = null


func before_test() -> void:
	FishCatalog.reload()
	Clock.reset_to_default()
	Clock.paused = true
	Clock.month = 6
	Clock.hour = 10
	_grid = WorldGrid.new()
	_grid.configure(16, 16, 2.0, Vector3(-16, 0, -16))
	for x: int in range(4, 12):
		for z: int in range(4, 12):
			_grid.set_terrain(Vector2i(x, z), WorldGrid.Terrain.WATER)
	_pond = WaterBodies.find(_grid)[0]


func after_test() -> void:
	Clock.reset_to_default()
	Clock.paused = false


func test_every_size_class_has_a_row_in_each_table() -> void:
	var sizes: int = FishData.SizeClass.size()
	assert_int(sizes).is_equal(8)
	assert_int(FishSize.SPEED_GX.size()).is_equal(sizes)
	assert_int(FishSize.BACK_SPEED_GX.size()).is_equal(sizes)
	assert_int(FishSize.TOUCH_FRAMES.size()).is_equal(sizes)
	assert_int(FishSize.TOUCH_DIST_GX.size()).is_equal(sizes)
	assert_int(FishSize.SHADOW_SCALE.size()).is_equal(sizes)
	assert_int(FishSize.HOOK_TRAIL_GX.size()).is_equal(sizes)


func test_bigger_fish_cast_bigger_shadows_and_swim_faster() -> void:
	var previous_area: float = 0.0
	var previous_speed: float = 0.0
	for size: int in FishData.SizeClass.size():
		var extent: Vector2 = FishSize.shadow_size(size as FishData.SizeClass)
		var area: float = extent.x * extent.y
		assert_float(area).is_greater(previous_area - 0.0001)
		assert_float(FishSize.speed(size as FishData.SizeClass)).is_greater(previous_speed - 0.0001)
		## `Matrix_scale(scale.x * 0.4, ...)`: always 2.5x longer than wide.
		assert_float(extent.y / extent.x).is_equal_approx(1.0 / FishSize.SHADOW_ASPECT, 0.001)
		previous_area = area
		previous_speed = FishSize.speed(size as FishData.SizeClass)
	## An XXS shadow is a smudge and an XXL is unmistakable, four times longer.
	var xxs: Vector2 = FishSize.shadow_size(FishData.SizeClass.XXS)
	var xxl: Vector2 = FishSize.shadow_size(FishData.SizeClass.XXL)
	assert_float(xxl.y / xxs.y).is_equal_approx(4.0, 0.01)


func test_search_cone_and_bite_window_come_from_the_species_row() -> void:
	## `aGYO_search_angle` normal rod: a fussy fish only sees 3 degrees off its nose.
	assert_float(rad_to_deg(FishSize.search_half_angle(0))).is_equal_approx(3.0, 0.001)
	assert_float(rad_to_deg(FishSize.search_half_angle(4))).is_equal_approx(180.0, 0.001)
	assert_float(FishSize.search_distance(0)).is_less(FishSize.search_distance(4))
	## `aGYO_bite_time * 2` frames at 60 Hz: a third of a second up to a lazy second and a half.
	assert_float(FishSize.bite_seconds(0)).is_equal_approx(20.0 / 60.0, 0.001)
	assert_float(FishSize.bite_seconds(4)).is_equal_approx(90.0 / 60.0, 0.001)


func test_swim_animation_holds_each_of_twenty_frames_for_two() -> void:
	## `fwork0` steps 0.5 per frame through 20 table entries: a 38-frame loop.
	assert_int(FishSize.anim_frame(0.0)).is_equal(0)
	assert_int(FishSize.anim_frame(STEP * 2.0)).is_equal(1)
	assert_int(FishSize.anim_frame(STEP * 4.0)).is_equal(2)
	## It wraps rather than running off the end.
	assert_int(FishSize.anim_frame(FishSize.ANIM_LOOP_SECONDS)).is_equal(0)
	assert_int(FishSize.anim_frame(FishSize.ANIM_LOOP_SECONDS * 3.0 + STEP * 21.0)).is_equal(10)
	## `aGYO_prim_f` is a ramp that peaks mid-sway and returns to zero, twice per loop.
	assert_float(FishSize.body_blend(4)).is_equal_approx(1.0, 0.001)
	assert_float(FishSize.body_blend(9)).is_equal_approx(0.0, 0.001)
	assert_float(FishSize.body_blend(14)).is_equal_approx(1.0, 0.001)
	## `aGYO_2tile_texture_idx`: the blended pair changes every fifth frame.
	assert_that(FishSize.tile_pair(0)).is_equal(Vector2i(0, 3))
	assert_that(FishSize.tile_pair(5)).is_equal(Vector2i(2, 3))
	assert_that(FishSize.tile_pair(19)).is_equal(Vector2i(0, 1))


func test_whale_shadow_never_wiggles() -> void:
	## `dec_step` is 0.0 for `aGYO_SIZE_WHALE`, so its shadow is frozen.
	var shadow: FishShadow = _shadow(FishData.SizeClass.WHALE, 4, 3, Vector3.ZERO)
	shadow.tick(1.0, FishShadow.Sense.new())
	assert_int(shadow.anim_frame()).is_equal(0)


func test_escape_puff_fades_out_over_the_last_forty_frames() -> void:
	## `(delete_timer * 0.5 - 10) * 6`: solid, then a fade, then gone at 100 frames. It peaks
	## at 240 rather than 255, so a puff is never quite as dark as the fish that left it.
	assert_float(FishSize.puff_alpha(0.0)).is_equal_approx(240.0 / 255.0, 0.001)
	assert_float(FishSize.puff_alpha(FishSize.puff_seconds())).is_equal(0.0)
	assert_float(FishSize.puff_alpha(60.0 / 60.0)).is_greater(0.0)
	assert_float(FishSize.puff_alpha(60.0 / 60.0)).is_less(1.0)
	assert_float(FishSize.puff_alpha(85.0 / 60.0)).is_equal(0.0)


func test_water_floods_into_separate_bodies() -> void:
	var grid := WorldGrid.new()
	grid.configure(16, 16, 2.0, Vector3.ZERO)
	## A round pond and, unconnected, a long channel.
	for x: int in range(2, 5):
		for z: int in range(2, 5):
			grid.set_terrain(Vector2i(x, z), WorldGrid.Terrain.WATER)
	for z: int in range(2, 14):
		grid.set_terrain(Vector2i(10, z), WorldGrid.Terrain.WATER)
	var bodies: Array[WaterBodies.Body] = WaterBodies.find(grid)
	assert_int(bodies.size()).is_equal(2)
	var pond: WaterBodies.Body = WaterBodies.body_at(bodies, Vector2i(3, 3))
	var river: WaterBodies.Body = WaterBodies.body_at(bodies, Vector2i(10, 8))
	assert_that(pond.kind).is_equal(WaterBodies.Kind.POND)
	assert_that(river.kind).is_equal(WaterBodies.Kind.RIVER)
	assert_bool(river.flows).is_true()
	assert_bool(pond.flows).is_false()
	## Bodies do not bleed into each other, so a fish cannot cross dry land.
	assert_bool(pond.contains(Vector2i(10, 8))).is_false()
	## A nine-cell puddle will not hold anything large.
	assert_that(WaterBodies.size_ceiling(pond)).is_equal(FishData.SizeClass.L)
	assert_that(WaterBodies.size_ceiling(river)).is_equal(FishData.SizeClass.XL)


func test_open_water_touching_the_map_edge_reads_as_ocean() -> void:
	var grid := WorldGrid.new()
	grid.configure(16, 16, 2.0, Vector3.ZERO)
	for x: int in 16:
		for z: int in range(0, 6):
			grid.set_terrain(Vector2i(x, z), WorldGrid.Terrain.WATER)
	var bodies: Array[WaterBodies.Body] = WaterBodies.find(grid)
	assert_int(bodies.size()).is_equal(1)
	assert_that(bodies[0].kind).is_equal(WaterBodies.Kind.OCEAN)
	## Only the sea gets to hold the biggest sizes.
	assert_that(WaterBodies.size_ceiling(bodies[0])).is_equal(FishData.SizeClass.WHALE)


func test_a_shadow_holds_station_then_wanders() -> void:
	var shadow: FishShadow = _shadow(FishData.SizeClass.M, 2, 3, _at(Vector2i(8, 8)))
	assert_that(shadow.action).is_equal(FishShadow.Action.WAIT)
	## `aGTT_wait_init`: 100-130 authored frames, doubled — three or four seconds of holding.
	var sense := FishShadow.Sense.new()
	_run(shadow, sense, FishSize.wait_seconds(1.0) + 0.1)
	assert_bool(
		shadow.action == FishShadow.Action.SWIM or shadow.action == FishShadow.Action.WAIT
	).is_true()
	## Whatever it did, it stayed in its pond.
	assert_bool(_pond.contains(_grid.world_to_cell(shadow.position))).is_true()


func test_a_fussy_fish_ignores_a_bobber_outside_its_cone() -> void:
	## `search_area` 0 is a 3 degree cone. The fish faces +Z; put the bobber on its flank,
	## well inside the 40 GX radius so only the cone can reject it.
	var flank: Vector3 = _at(Vector2i(8, 8)) + Vector3(-1.5, 0.0, 0.0)
	var shadow: FishShadow = _shadow(FishData.SizeClass.L, 0, 1, _at(Vector2i(8, 8)))
	shadow.yaw = 0.0
	_run(shadow, _bobber_sense(flank), 0.5)
	## It never engages: it is still holding station or wandering.
	assert_bool(
		shadow.action == FishShadow.Action.WAIT or shadow.action == FishShadow.Action.SWIM
	).is_true()
	## The same fish with a 180 degree cone notices it immediately. An L closes 1.5 m in a
	## fraction of a second, so by now it is approaching or already plucking at the bobber.
	var eager: FishShadow = _shadow(FishData.SizeClass.L, 4, 1, _at(Vector2i(8, 8)))
	eager.yaw = 0.0
	_run(eager, _bobber_sense(flank), 0.5)
	assert_bool(
		eager.action == FishShadow.Action.NEAR or eager.action == FishShadow.Action.TOUCH
	).is_true()


func test_a_fish_nibbles_several_times_before_it_commits() -> void:
	var shadow: FishShadow = _shadow(FishData.SizeClass.XXS, 4, 4, _at(Vector2i(8, 9)))
	var bobber: Vector3 = _at(Vector2i(8, 8))
	var sense: FishShadow.Sense = _bobber_sense(bobber)
	var nibbles: int = 0
	var elapsed: float = 0.0
	while elapsed < 30.0 and shadow.action != FishShadow.Action.BITE:
		shadow.tick(STEP, sense)
		if shadow.nibbled:
			nibbles += 1
		elapsed += STEP
	assert_that(shadow.action).is_equal(FishShadow.Action.BITE)
	## `touch_counter = 5` with a 1-in-4 commit chance: it plucks at least once and at most
	## four times before the fifth approach is forced.
	assert_int(nibbles).is_between(1, 4)
	assert_bool(shadow.is_hooked()).is_true()


func test_a_dashing_player_scares_a_fish_into_a_puff() -> void:
	var school := FishSchool.new()
	school.configure(_grid, 0.0)
	school.auto_spawn = false
	school.seed_rng(3)
	var fish: FishData = FishCatalog.get_fish(&"crucian_carp")
	var shadow: FishShadow = school.spawn(fish, _pond, _at(Vector2i(8, 8)))
	assert_that(shadow).is_not_null()
	var sense := FishShadow.Sense.new()
	## `aGTT_player_near`: walking past is fine, dashing is not.
	sense.player_position = _at(Vector2i(8, 9))
	sense.player_dashing = false
	school.tick(STEP, sense)
	assert_int(school.shadow_count()).is_equal(1)
	assert_int(school.puffs.size()).is_equal(0)
	sense.player_dashing = true
	school.tick(STEP, sense)
	assert_int(school.shadow_count()).is_equal(0)
	## `aGTT_kage_make_actor`: it leaves a fading shadow darting away behind it.
	assert_int(school.puffs.size()).is_equal(1)
	assert_float(school.puffs[0].alpha()).is_greater(0.0)
	school.tick(FishSize.puff_seconds() + 0.1, sense)
	assert_int(school.puffs.size()).is_equal(0)


func test_school_stocks_water_up_to_two_shadows() -> void:
	var school := FishSchool.new()
	school.configure(_grid, 0.0)
	school.seed_rng(11)
	assert_bool(school.has_water()).is_true()
	var sense := FishShadow.Sense.new()
	sense.player_position = _at(Vector2i(8, 8))
	## `aGYO_MAX_GYOEI`: two at once and no more, however long it runs.
	for _i: int in 400:
		school.tick(STEP * 4.0, sense)
		assert_int(school.shadow_count()).is_less_equal(FishSchool.MAX_SHADOWS)
	assert_int(school.shadow_count()).is_equal(FishSchool.MAX_SHADOWS)
	for shadow: FishShadow in school.shadows:
		assert_that(shadow.fish).is_not_null()
		## Nothing spawns that the pond is too small to hold.
		assert_int(int(shadow.fish.size_class)).is_less_equal(
			int(WaterBodies.size_ceiling(shadow.body))
		)
		## Shadows ride under the surface, not on it.
		assert_float(shadow.position.y).is_equal_approx(-FishSize.depth(), 0.001)


func test_a_school_with_no_water_never_spawns() -> void:
	var dry := WorldGrid.new()
	dry.configure(8, 8, 2.0, Vector3.ZERO)
	var school := FishSchool.new()
	school.configure(dry, 0.0)
	assert_bool(school.has_water()).is_false()
	var sense := FishShadow.Sense.new()
	sense.player_position = Vector3.ZERO
	for _i: int in 100:
		school.tick(STEP * 4.0, sense)
	assert_int(school.shadow_count()).is_equal(0)


func _at(cell: Vector2i) -> Vector3:
	return _grid.cell_to_world(cell)


func _shadow(
	size: FishData.SizeClass, search_area: int, bite_time: int, at: Vector3
) -> FishShadow:
	var fish := FishData.new()
	fish.id = &"probe"
	fish.size_class = size
	fish.search_area = search_area
	fish.bite_time = bite_time
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var shadow: FishShadow = FishShadow.create(fish, _pond, at, rng)
	shadow.cell_lookup = _grid.world_to_cell
	return shadow


func _bobber_sense(at: Vector3) -> FishShadow.Sense:
	var sense := FishShadow.Sense.new()
	sense.bobber_position = at
	sense.bobber_settled = true
	sense.accepts_nibble = true
	sense.accepts_bite = true
	return sense


func _run(shadow: FishShadow, sense: FishShadow.Sense, seconds: float) -> void:
	var elapsed: float = 0.0
	while elapsed < seconds:
		shadow.tick(STEP, sense)
		elapsed += STEP
