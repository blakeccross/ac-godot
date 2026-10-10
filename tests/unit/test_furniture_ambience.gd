class_name TestFurnitureAmbience
extends GdUnitTestSuite

## What furniture gives off while it is out (`FurnitureAmbience`): level SEs from the
## furniture move procs and the steam off hot food.


func _piece(visual: StringName) -> FurnitureData:
	var d := FurnitureData.new()
	d.id = visual
	d.visual_id = visual
	return d


func _entry(on: bool) -> FurniturePlacement:
	var e := FurniturePlacement.new()
	e.id = &"p1"
	e.on = on
	return e


func test_fires_crackle_whatever_the_switch() -> void:
	var fire := _piece(&"int_ike_kama_danro01")
	assert_int(FurnitureAmbience.level_for(fire, _entry(true))).is_equal(0x46)
	assert_int(FurnitureAmbience.level_for(fire, _entry(false))).is_equal(0x46)
	assert_bool(FurnitureAmbience.switchable(fire)).is_false()
	assert_str(String(BugSounds.se_id(0x46))).is_equal("lev_46")


func test_a_tv_sounds_only_switched_on_and_clicks() -> void:
	var tv := _piece(&"int_sum_tv01")
	assert_int(FurnitureAmbience.level_for(tv, _entry(true))).is_equal(5)
	assert_int(FurnitureAmbience.level_for(tv, _entry(false))).is_equal(-1)
	assert_bool(FurnitureAmbience.switchable(tv)).is_true()
	assert_bool(FurnitureAmbience.clicks(tv)).is_true()
	## A plain chair is silent.
	assert_int(FurnitureAmbience.level_for(_piece(&"int_sum_chair01"), _entry(true))).is_equal(-1)


func test_the_pot_boils_with_its_switch_off() -> void:
	var pot := _piece(&"int_nog_nabe")
	assert_int(FurnitureAmbience.level_for(pot, _entry(false))).is_equal(0x50)
	assert_int(FurnitureAmbience.level_for(pot, _entry(true))).is_equal(-1)


func test_only_rooms_with_furniture_actors_sound() -> void:
	var tv: FurnitureData = ItemCatalog.get_item(&"wood_tv") as FurnitureData
	var room := Room.new()
	room.kind = Room.Kind.PLAYER
	var entry := _entry(true)
	entry.furniture_id = tv.id
	room.placements = [entry]
	var session := IndoorSession.new()
	session.bind(room)
	assert_array(FurnitureAmbience.sources(session)).is_equal([[&"p1", 5]])
	room.kind = Room.Kind.SHOP
	assert_array(FurnitureAmbience.sources(session)).is_empty()


func test_the_stew_steams_every_eight_ticks() -> void:
	var stew := _piece(&"int_tak_stew")
	var rng := RandomNumberGenerator.new()
	var puffs: int = 0
	var wait: Array = [-1]
	for tick: int in range(1, 65):
		if FurnitureAmbience.steams(stew, _entry(true), tick, wait, rng):
			puffs += 1
	assert_int(puffs).is_equal(8)


func test_the_hot_pot_puffs_every_ten_to_thirty_ticks_while_boiling() -> void:
	var pot := _piece(&"int_nog_nabe")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var wait: Array = [-1]
	var at: Array[int] = []
	for tick: int in 200:
		if FurnitureAmbience.steams(pot, _entry(false), tick, wait, rng):
			at.append(tick)
	assert_int(at.size()).is_greater(5)
	for i: int in range(1, at.size()):
		assert_int(at[i] - at[i - 1]).is_between(12, 31)
	assert_bool(FurnitureAmbience.steams(pot, _entry(true), 0, [-1], rng)).is_false()


func test_steam_rises_and_thins() -> void:
	var host: Node3D = auto_free(Node3D.new())
	add_child(host)
	var fx: FieldFx = FieldFx.spawn(host, FieldFx.Kind.SOBA_YUGE, Vector3.ZERO, 0.0, 10, 0)
	assert_object(fx).is_not_null()
	assert_int(fx.timer).is_equal(44)
	var y0: float = fx.pos_gx.y
	for _i: int in 20:
		fx._move()
	assert_float(fx.pos_gx.y).is_greater(y0)
	assert_float(Vector2(fx.pos_gx.x, fx.pos_gx.z).length()).is_equal_approx(10.0, 0.01)


func test_a_gong_sounds_when_struck_and_the_piggy_bank_needs_bells() -> void:
	var gong := _piece(&"int_nog_gong")
	assert_bool(FurnitureAmbience.switchable(gong)).is_true()
	assert_str(String(FurnitureAmbience.press_se(gong, 0))).is_equal("174")
	var pig := _piece(&"int_ike_pst_pig01")
	assert_str(String(FurnitureAmbience.press_se(pig, 0))).is_equal("")
	assert_str(String(FurnitureAmbience.press_se(pig, 100))).is_equal("7c")
	assert_str(String(FurnitureAmbience.press_se(_piece(&"int_sum_tv01"), 0))).is_equal("")


func test_a_looping_clip_sounds_as_it_passes_its_frame() -> void:
	assert_bool(FurnitureAmbience.crossed(19.5, 20.5, 20.0)).is_true()
	assert_bool(FurnitureAmbience.crossed(20.0, 21.0, 20.0)).is_false()
	## Wrapping from the clip's end to its start.
	assert_bool(FurnitureAmbience.crossed(39.0, 2.0, 1.0)).is_true()
	assert_bool(FurnitureAmbience.crossed(39.0, 2.0, 20.0)).is_false()
	## Nothing on the first read.
	assert_bool(FurnitureAmbience.crossed(-1.0, 20.0, 20.0)).is_false()


func test_fish_tanks_and_cages_loop_their_clips() -> void:
	if not FurnitureProfiles.available():
		return
	assert_bool(FurnitureData.loops_idle(&"int_sum_raigyo")).is_true()
	assert_bool(FurnitureData.loops_idle(&"int_sum_chair01")).is_false()
