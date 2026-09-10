class_name TestFishBehavior
extends GdUnitTestSuite

## Decomp-faithful fish extras: the golden rod (`aGYO_get_uki_type`), the 1-in-20
## trash swap (`aGTT_touch` / `gomi[]`), and the `aSOG_gyoei_set` spawn scheduler
## (`fish_spawn_scheduler.gd` + `data/creatures/fish_spawn_table.json`).

func before_test() -> void:
	Game.reset_session()
	FishCatalog.reload()
	FishSpawnScheduler.reload()
	Clock.reset_to_default()
	Clock.paused = true


# ---- golden rod ------------------------------------------------------

func test_golden_rod_widens_search_and_lengthens_bite() -> void:
	## `aGYO_search_angle` / `aGYO_bite_time` rows: golden sees wider (not further) and
	## holds the hook longer.
	for area: int in 5:
		assert_float(FishSize.search_distance(area, FishSize.ROD_GOLDEN)).is_equal(
			FishSize.search_distance(area, FishSize.ROD_NORMAL)
		)
	assert_float(FishSize.search_half_angle(2, FishSize.ROD_GOLDEN)).is_greater(
		FishSize.search_half_angle(2, FishSize.ROD_NORMAL)
	)
	assert_float(FishSize.bite_seconds(4, FishSize.ROD_GOLDEN)).is_greater(
		FishSize.bite_seconds(4, FishSize.ROD_NORMAL)
	)
	## The 3° fussy cone doubles to 7.5° on the golden rod.
	assert_float(FishSize.search_half_angle(0, FishSize.ROD_GOLDEN)).is_equal_approx(
		deg_to_rad(7.5), 0.001
	)


func test_shadow_reads_the_rod_from_the_sense() -> void:
	var body := WaterBodies.Body.new()
	var fish: FishData = FishCatalog.get_fish(&"large_char")   ## search_area 1 → 7° normal
	var shadow := FishShadow.create(fish, body, Vector3.ZERO, RandomNumberGenerator.new())
	shadow.action = FishShadow.Action.NEAR
	shadow.yaw = 0.0
	var s := FishShadow.Sense.new()
	s.bobber_settled = true
	s.accepts_nibble = true
	shadow.yaw = 0.0
	shadow.action = FishShadow.Action.WAIT
	shadow._timer = 999.0
	## Within the 40 GX (2 m) radius, off to one side by ~10° — outside the 7° normal
	## cone (`search_area` 1), inside the 15° golden one.
	var d: float = 1.5
	s.bobber_position = Vector3(sin(deg_to_rad(10.0)) * d, 0.0, cos(deg_to_rad(10.0)) * d)

	s.rod = FishSize.ROD_NORMAL
	shadow.tick(1.0 / 30.0, s)
	assert_int(shadow.action).is_equal(FishShadow.Action.WAIT)   ## fussy — misses it

	shadow.action = FishShadow.Action.WAIT
	shadow._timer = 999.0
	shadow.yaw = 0.0
	s.rod = FishSize.ROD_GOLDEN
	shadow.tick(1.0 / 30.0, s)
	assert_int(shadow.action).is_equal(FishShadow.Action.NEAR)   ## golden — spots it


# ---- trash swap ----------------------------------------------------

func test_committing_fish_can_turn_out_to_be_trash() -> void:
	## `aGTT_touch`: 1 time in 20, `gyo_type` swaps to `gomi[size]`.
	assert_str(String(FishCatalog.trash_for_size(FishData.SizeClass.XXS).id)).is_equal("empty_can")
	assert_str(String(FishCatalog.trash_for_size(FishData.SizeClass.M).id)).is_equal("leaky_boot")
	assert_str(String(FishCatalog.trash_for_size(FishData.SizeClass.XL).id)).is_equal("old_tire")

	var body := WaterBodies.Body.new()
	var got_trash := false
	for _i: int in 400:
		var rng := RandomNumberGenerator.new()
		rng.seed = _i
		var shadow := FishShadow.create(FishCatalog.get_fish(&"bass"), body, Vector3.ZERO, rng)
		var s := FishShadow.Sense.new()
		s.bobber_position = Vector3(0.0, 0.0, 0.05)
		s.bobber_settled = true
		s.accepts_nibble = true
		s.accepts_bite = true
		s.has_pocket_space = true
		shadow.action = FishShadow.Action.TOUCH
		shadow._timer = 0.0
		shadow._nibbles_left = 1   ## force the commit
		shadow.tick(1.0 / 30.0, s)
		if shadow.action == FishShadow.Action.BITE and shadow.fish.is_trash:
			got_trash = true
			break
	assert_bool(got_trash).is_true()


func test_full_pockets_block_the_trash_swap() -> void:
	## `mPlib_Get_space_putin_item() >= 0` gates the swap.
	var body := WaterBodies.Body.new()
	for _i: int in 200:
		var rng := RandomNumberGenerator.new()
		rng.seed = _i
		var shadow := FishShadow.create(FishCatalog.get_fish(&"carp"), body, Vector3.ZERO, rng)
		var s := FishShadow.Sense.new()
		s.bobber_position = Vector3(0.0, 0.0, 0.05)
		s.bobber_settled = true
		s.accepts_nibble = true
		s.accepts_bite = true
		s.has_pocket_space = false
		shadow.action = FishShadow.Action.TOUCH
		shadow._timer = 0.0
		shadow._nibbles_left = 1
		shadow.tick(1.0 / 30.0, s)
		if shadow.action == FishShadow.Action.BITE:
			assert_bool(shadow.fish.is_trash).is_false()


# ---- spawn scheduler --------------------------------------------

func test_spawn_table_loads_all_24_half_month_terms() -> void:
	FishSpawnScheduler.ensure_loaded()
	Clock.month = 1
	Clock.day = 1
	Clock.hour = 12
	var pool: Array = FishSpawnScheduler.build_pool(WaterBodies.Kind.RIVER, false)
	assert_int(pool.size()).is_greater(5)
	var has_pond_smelt := false
	for e: Dictionary in pool:
		if int(e["type_index"]) == 16:   ## pond smelt — heavy in the January river
			has_pond_smelt = true
	assert_bool(has_pond_smelt).is_true()


func test_scheduler_blends_the_previous_half_month() -> void:
	Clock.month = 9
	Clock.day = 1
	Clock.hour = 12
	Game.gyoei_term = (9 - 1) * 2      ## already rolled; pin offset 0
	Game.gyoei_term_offset = 0
	var blend: Dictionary = FishSpawnScheduler.term_blend(null)
	assert_int(int(blend["term"])).is_equal(16)          ## Sep first half
	assert_int(int(blend["prev_term"])).is_equal(15)     ## Aug second half
	assert_float(float(blend["prev_rate"])).is_greater(0.0)


func test_coelacanth_is_spliced_into_the_rainy_sea() -> void:
	Clock.month = 6
	Clock.day = 10
	Clock.hour = 2                      ## night — not the day slot
	var wet: Array = FishSpawnScheduler.build_pool(WaterBodies.Kind.OCEAN, true)
	var dry: Array = FishSpawnScheduler.build_pool(WaterBodies.Kind.OCEAN, false)
	assert_bool(_has_type(wet, 31)).is_true()
	assert_bool(_has_type(dry, 31)).is_false()


func test_scheduler_respects_the_body_size_ceiling() -> void:
	Clock.month = 7
	Clock.day = 10
	Clock.hour = 12
	var pool: Array = FishSpawnScheduler.build_pool(WaterBodies.Kind.OCEAN, false)
	var rng := RandomNumberGenerator.new()
	for _i: int in 60:
		rng.seed = _i
		var fish: FishData = FishSpawnScheduler.decide(pool, FishData.SizeClass.S, rng)
		if fish != null:
			assert_int(int(fish.size_class)).is_less_equal(int(FishData.SizeClass.S))


func _has_type(pool: Array, type_index: int) -> bool:
	for e: Dictionary in pool:
		if int(e["type_index"]) == type_index:
			return true
	return false
