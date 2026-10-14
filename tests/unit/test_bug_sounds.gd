class_name TestBugSounds
extends GdUnitTestSuite

## Insect sounds: the programs' `sAdo_OngenPos` level SEs (`BugActor.ongen`) and
## `sAdo_OngenTrgStart` one-shots (`trg_se`), and `BugSounds` picking what to play.

var _rng: RandomNumberGenerator = null


func before_test() -> void:
	BugCatalog.reload()
	Clock.reset_to_default()
	Clock.paused = true
	_rng = RandomNumberGenerator.new()
	_rng.seed = 7


func _make(id: StringName, hab: BugData.Habitat, at: Vector3, released: bool = false) -> BugActor:
	return BugActor.create(BugCatalog.get_bug(id), hab, at, _rng, released)


## Every level SE an actor raised over `frames` frames.
func _heard(a: BugActor, frames: int, s: BugActor.Sense) -> Array[int]:
	var out: Array[int] = []
	for _i: int in frames:
		a.frame(s)
		if a.ongen >= 0 and not out.has(a.ongen):
			out.append(a.ongen)
		if a.finished:
			break
	return out


func test_a_calm_cicada_cries_its_own_song() -> void:
	var songs := {&"robust_cicada": 0x9B, &"walker_cicada": 0x9A, &"evening_cicada": 0x98, &"brown_cicada": 0x97}
	for id: StringName in songs:
		var a := _make(id, BugData.Habitat.TREE, Vector3(9.0, 2.0, 13.0))
		assert_array(_heard(a, 150, BugActor.Sense.new())) \
			.append_failure_message(String(id)).contains([songs[id]])


func test_cicadas_hush_in_the_rain() -> void:
	var a := _make(&"robust_cicada", BugData.Habitat.TREE, Vector3(9.0, 2.0, 13.0))
	var s := BugActor.Sense.new()
	s.raining = true
	assert_array(_heard(a, 150, s)).is_empty()


func test_a_startled_cicada_shrieks_once() -> void:
	var a := _make(&"robust_cicada", BugData.Habitat.TREE, Vector3(9.0, 2.0, 13.0))
	a.patience = 100.0
	a.frame(BugActor.Sense.new())
	assert_int(a.action).is_equal(BugSemi.AVOID)
	assert_array(a.trg_se).contains_exactly([&"semi_escape"])


func test_bees_buzz_only_as_they_fly_off() -> void:
	var a := _make(&"bee", BugData.Habitat.TREE, Vector3(9.0, 2.0, 13.0))
	assert_array(_heard(a, 60, BugActor.Sense.new())).is_empty()
	a.patience = 100.0
	a.frame(BugActor.Sense.new())
	assert_array(a.trg_se).is_empty()
	assert_array(_heard(a, 5, BugActor.Sense.new())).contains_exactly([0x26])


func test_a_mosquito_whines_until_it_bites() -> void:
	var a := _make(&"mosquito", BugData.Habitat.FLYING, Vector3(4.0, 1.5, 4.0))
	a.frame(BugActor.Sense.new())
	assert_int(a.ongen).is_equal(0xCF)
	BugKa.new().setup_action(a, BugKa.ATTACK)
	assert_array(a.trg_se).contains_exactly([&"6a"])


func test_resting_crickets_sing_and_locusts_whirr_in_flight() -> void:
	var songs := {&"cricket": 0x9F, &"grasshopper": 0x9E, &"bell_cricket": 0xA0, &"pine_cricket": 0x9D}
	for id: StringName in songs:
		var a := _make(id, BugData.Habitat.BUSH, Vector3(8.0, 0.0, 8.0))
		assert_array(_heard(a, 90, BugActor.Sense.new())) \
			.append_failure_message(String(id)).contains([songs[id]])
	var locust := _make(&"migratory_locust", BugData.Habitat.GROUND, Vector3(8.0, 0.0, 8.0))
	locust.patience = 100.0
	assert_array(_heard(locust, 30, BugActor.Sense.new())).contains([0xA3])


func test_drowning_hoppers_splash() -> void:
	var a := _make(&"grasshopper", BugData.Habitat.GROUND, Vector3(8.0, 0.0, 8.0))
	BugBatta.new().setup_action(a, BugBatta.DROWN)
	assert_array(a.trg_se).contains_exactly([&"438"])


func test_a_field_keeps_the_splash_of_an_insect_it_drops() -> void:
	var field := BugField.new()
	var a := _make(&"grasshopper", BugData.Habitat.GROUND, Vector3(8.0, 0.0, 8.0))
	BugBatta.new().setup_action(a, BugBatta.DROWN)
	field.actors.append(a)
	field._frame(BugActor.Sense.new())
	assert_array(field.actors).is_empty()
	assert_int(field.gone_se.size()).is_equal(1)
	assert_str(String(field.gone_se[0][0])).is_equal("438")


func test_pick_takes_the_nearest_sounding_insects_in_range() -> void:
	var gx: float = FieldCatalog.GX_TO_METERS
	var far := _make(&"cricket", BugData.Habitat.BUSH, Vector3(300.0 * gx, 0.0, 0.0))
	var near := _make(&"cricket", BugData.Habitat.BUSH, Vector3(100.0 * gx, 0.0, 0.0))
	var quiet := _make(&"cricket", BugData.Habitat.BUSH, Vector3(10.0 * gx, 0.0, 0.0))
	var gone := _make(&"cricket", BugData.Habitat.BUSH, Vector3(600.0 * gx, 0.0, 0.0))
	for a: BugActor in [far, near, gone]:
		a.ongen = 0x9F
	quiet.ongen = -1
	var picked: Array = BugSounds.pick([far, near, quiet, gone], Vector3.ZERO, 4)
	assert_int(picked.size()).is_equal(2)
	assert_object(picked[0][0]).is_same(near)
	assert_object(picked[1][0]).is_same(far)
	assert_float(float(picked[0][1])).is_equal_approx(100.0, 0.5)
	assert_int(BugSounds.pick([far, near], Vector3.ZERO, 1).size()).is_equal(1)


func test_level_ids_name_the_lev_renders() -> void:
	assert_str(String(BugSounds.se_id(0x9B))).is_equal("lev_9b")
	assert_str(String(BugSounds.se_id(0xCF))).is_equal("lev_cf")
