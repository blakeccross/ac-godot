class_name TestInteriorLightModel
extends GdUnitTestSuite

## `InteriorLightModel` against `m_kankyo.c` numbers.


func before_test() -> void:
	InteriorCatalog.reset()


func after_test() -> void:
	InteriorCatalog.reset()


func _room(id: StringName) -> Room:
	return InteriorCatalog.room_template(id)


func _sec(hour: int) -> int:
	return hour * 3600


func test_home_uses_outdoor_ambient_not_room_colour() -> void:
	## 12:00 fine: ambient (80, 80, 150); room colour only tints PRIM surfaces.
	var light: Dictionary = InteriorLightModel.evaluate(_room(&"npc_filbert"), _sec(12), false, false)
	assert_that(light["ambient"]).is_equal(Color8(80, 80, 150))


func test_home_sun_scaled_by_switch_and_lamp() -> void:
	## 12:00 sun (200, 240, 240) × 0.7 × (1 − 0.6 × percent).
	var off: Dictionary = InteriorLightModel.evaluate(_room(&"player_main"), _sec(12), false, false)
	var on: Dictionary = InteriorLightModel.evaluate(_room(&"player_main"), _sec(12), false, true)
	var k_off: float = 0.7 * (1.0 - 0.6 * InteriorLightModel.POINT_LIGHT_MIN)
	assert_float((off["sun"] as Color).g).is_equal_approx(240.0 / 255.0 * k_off, 0.001)
	assert_float((on["sun"] as Color).g).is_equal_approx(240.0 / 255.0 * 0.7 * 0.4, 0.001)
	assert_float((off["lamp_color"] as Color).r).is_equal_approx(220.0 / 255.0 * 0.14, 0.001)
	assert_that(on["lamp_color"]).is_equal(Color8(220, 220, 200))


func test_room_prim_matches_get_room_prim_color() -> void:
	## 20:00–24:00 room (130, 160, 160), lamp on: c × 0.7 × 0.7 + lamp × 0.6.
	var light: Dictionary = InteriorLightModel.evaluate(_room(&"npc_filbert"), _sec(20), false, true)
	assert_that(light["room_prim"]).is_equal(Color8(195, 210, 198))
	## Public room without a switch: lamp always on, no 0.7 rate. Kamakura-style flame averages.
	var shop: Dictionary = InteriorLightModel.evaluate(_room(&"shop0"), _sec(12), false, false)
	assert_that(shop["room_prim"]).is_equal(Color8(255, 255, 255))
	var snow: Dictionary = InteriorLightModel.evaluate(_room(&"kamakura"), _sec(12), false, true)
	assert_that(snow["room_prim"]).is_equal(Color8(250, 240, 140))


func test_fixed_palette_rooms() -> void:
	var fish: Dictionary = InteriorLightModel.evaluate(_room(&"museum_fish"), _sec(3), false, true)
	assert_that(fish["ambient"]).is_equal(Color8(40, 50, 60))
	assert_that(fish["sun_dir"]).is_equal(Vector3(0, 69, 97))
	var super_shop: Dictionary = InteriorLightModel.evaluate(_room(&"shop2"), _sec(22), false, true)
	assert_that(super_shop["ambient"]).is_equal(Color8(20, 10, 100))
	assert_that(super_shop["lamp_color"]).is_equal(Color8(160, 160, 160))


func test_rain_and_insect_scale_fine_table() -> void:
	var rain: Dictionary = InteriorLightModel.evaluate(_room(&"post_office"), _sec(12), true, true)
	assert_float((rain["ambient"] as Color).b).is_equal_approx(150.0 / 255.0 * 0.9, 0.001)
	var insect_night: Dictionary = InteriorLightModel.evaluate(_room(&"museum_insect"), _sec(1), false, true)
	assert_float((insect_night["ambient"] as Color).b).is_equal_approx(120.0 / 255.0 * 0.6, 0.001)
	var insect_day: Dictionary = InteriorLightModel.evaluate(_room(&"museum_insect"), _sec(12), false, true)
	assert_that(insect_day["ambient"]).is_equal(Color8(80, 80, 150))


func test_lamp_switch_rules() -> void:
	var npc: Room = _room(&"npc_filbert")
	assert_bool(InteriorLightModel.lamp_on(npc, 22, true)).is_true()
	assert_bool(InteriorLightModel.lamp_on(npc, 22, false)).is_false()
	assert_bool(InteriorLightModel.lamp_on(npc, 12, true)).is_false()
	assert_bool(InteriorLightModel.lamp_on(_room(&"player_main"), 4, false)).is_true()
	assert_bool(InteriorLightModel.lamp_on(_room(&"player_main"), 5, false)).is_false()
	assert_bool(InteriorLightModel.lamp_on(_room(&"shop0"), 12, false)).is_true()


func test_player_lamp_moves_with_house_size() -> void:
	var small: Dictionary = InteriorLightModel.scene_profile(_room(&"player_main"), House.SizeTier.SMALL)
	var large: Dictionary = InteriorLightModel.scene_profile(_room(&"player_main"), House.SizeTier.LARGE)
	assert_that(small["lamp_pos"]).is_equal(Vector3(120, 180, 180))
	assert_that(large["lamp_pos"]).is_equal(Vector3(200, 220, 300))
