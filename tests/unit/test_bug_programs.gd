class_name TestBugPrograms
extends GdUnitTestSuite

## Per-program movement state machines (`ac_ins_*.c`). Each `BugActor` is driven at
## 30 Hz via `frame()`; `tick(1.0/30.0, ...)` is the standalone equivalent.

var _rng: RandomNumberGenerator = null


func before_test() -> void:
	BugCatalog.reload()
	BugSpawnTable.reload()
	Clock.reset_to_default()
	Clock.paused = true
	_rng = RandomNumberGenerator.new()
	_rng.seed = 7


func _make(id: StringName, hab: BugData.Habitat, at: Vector3, released: bool = false) -> BugActor:
	return BugActor.create(BugCatalog.get_bug(id), hab, at, _rng, released)


func _run(a: BugActor, frames: int, s: BugActor.Sense) -> void:
	for _i: int in frames:
		a.frame(s)
		if a.finished:
			return


# ---- CHOU (butterfly) --------------------------------------------------

func test_field_butterfly_starts_flying_and_flutters() -> void:
	var b := _make(&"common_butterfly", BugData.Habitat.FLYING, Vector3(4.0, 0.5, 4.0))
	assert_int(b.action).is_equal(BugChou.FLY)
	var start: Vector3 = b.position
	_run(b, 90, BugActor.Sense.new())
	assert_bool(b.finished).is_false()
	assert_float(b.position.distance_to(start)).is_greater(0.05)


func test_butterfly_anime_pose_flips_at_frame_five() -> void:
	## `aICH_anime_proc`: `_1E0 += 0.2`; pose = `(int)_1E0`. 0.2*5 == 1.0.
	var b := _make(&"common_butterfly", BugData.Habitat.FLYING, Vector3.ZERO)
	assert_int(b.pose_index()).is_equal(0)
	_run(b, 4, BugActor.Sense.new())
	assert_int(b.pose_index()).is_equal(0)
	_run(b, 1, BugActor.Sense.new())
	assert_int(b.pose_index()).is_equal(1)


func test_common_butterfly_does_not_panic_flee_from_a_runner() -> void:
	## `aICH_fly` for common / yellow only calls `rest_check` — never `AVOID`, and
	## the shared framework only forces `LET_ESCAPE` on catch / lifetime / leaving
	## the acre. A charging player cannot scare it.
	var b := _make(&"common_butterfly", BugData.Habitat.FLYING, Vector3(4.0, 0.5, 4.0))
	var s := BugActor.Sense.new()
	for i in 200:
		s.player_position = b.position + Vector3(sin(i * 0.3) * 0.3, 0.0, cos(i * 0.3) * 0.3)
		s.player_move_gx = 7.5
		b.frame(s)
		assert_int(b.action).is_not_equal(BugChou.AVOID)
		assert_int(b.action).is_not_equal(BugChou.LET_ESCAPE)
	assert_bool(b.finished).is_false()


func test_tiger_butterfly_avoids_when_patience_high() -> void:
	var b := _make(&"tiger_butterfly", BugData.Habitat.FLYING, Vector3(4.0, 0.5, 4.0))
	b.patience = 95.0
	b.frame(BugActor.Sense.new())
	assert_int(b.action).is_equal(BugChou.AVOID)


func test_butterfly_leaving_acre_escapes_and_fades() -> void:
	var b := _make(&"common_butterfly", BugData.Habitat.FLYING, Vector3(4.0, 0.5, 4.0))
	b.pos = b.home + Vector3(9.0 * BugActor.UNIT_GX, 0.0, 0.0)
	b.frame(BugActor.Sense.new())
	assert_int(b.action).is_equal(BugChou.LET_ESCAPE)
	assert_int(b.alpha_time).is_equal(0x50)
	_run(b, 90, BugActor.Sense.new())
	assert_bool(b.finished).is_true()


func test_caught_butterfly_finishes() -> void:
	var b := _make(&"common_butterfly", BugData.Habitat.FLYING, Vector3.ZERO)
	b.catch()
	assert_bool(b.finished).is_true()
	assert_bool(b.caught).is_true()


# ---- KABUTO (beetle) --------------------------------------------------

func test_field_beetle_clings_to_trunk_facing_south() -> void:
	var anchor := Vector3(9.0, 0.0, 13.0)
	var b := _make(&"drone_beetle", BugData.Habitat.TREE, anchor)
	assert_int(b.action).is_equal(BugKabuto.WAIT)
	assert_float(b.pitch).is_equal_approx(PI * 0.5, 0.001)
	assert_float(b.position.y).is_greater(anchor.y)
	assert_float(absf(angle_difference(b.yaw, -BugActor.TREE_FACE_YAW))).is_less(0.001)


func test_beetle_sway_stays_within_five_degrees_of_south() -> void:
	var b := _make(&"drone_beetle", BugData.Habitat.TREE, Vector3(9.0, 0.0, 13.0))
	_run(b, 300, BugActor.Sense.new())
	assert_float(absf(angle_difference(b.yaw, -BugActor.TREE_FACE_YAW))).is_less(deg_to_rad(6.0))
	assert_bool(b.finished).is_false()


func test_beetle_scared_by_tree_shake_flies_up_and_away() -> void:
	var b := _make(&"drone_beetle", BugData.Habitat.TREE, Vector3(9.0, 2.0, 13.0))
	var start_y: float = b.position.y
	var s := BugActor.Sense.new()
	s.player_position = Vector3(9.0, 0.0, 14.0)
	s.player_action = BugActor.PlAct.SHAKE_TREE
	b.frame(s)
	assert_int(b.action).is_equal(BugKabuto.AVOID)
	assert_float(b.pitch).is_equal(0.0)
	_run(b, 40, s)
	assert_float(b.position.y).is_greater(start_y)


func test_beetle_net_scare_range_is_angular() -> void:
	var b := _make(&"drone_beetle", BugData.Habitat.TREE, Vector3(9.0, 2.0, 13.0))
	b.rot.y = 0.0
	## Player facing the same way as the beetle → catchable (24 GX).
	assert_float(b.net_catch_range_gx(0.0, 0.0)).is_equal(24.0)
	## Player facing 180° away → 0.
	assert_float(b.net_catch_range_gx(PI, 0.0)).is_equal(0.0)


# ---- every program: smoke ----------------------------------------

func test_every_species_ticks_without_crashing() -> void:
	## Field spawn + 300 frames with a roaming player. No NaNs; a live bug that
	## never fled stays within its acre-ish leash.
	var habs := {
		&"common_butterfly": BugData.Habitat.FLOWER,
		&"tiger_butterfly": BugData.Habitat.FLOWER,
		&"robust_cicada": BugData.Habitat.TREE,
		&"brown_cicada": BugData.Habitat.TREE,
		&"bee": BugData.Habitat.TREE,
		&"common_dragonfly": BugData.Habitat.FLYING,
		&"red_dragonfly": BugData.Habitat.FLYING,
		&"banded_dragonfly": BugData.Habitat.FLYING,
		&"grasshopper": BugData.Habitat.GROUND,
		&"migratory_locust": BugData.Habitat.GROUND,
		&"cricket": BugData.Habitat.BUSH,
		&"drone_beetle": BugData.Habitat.TREE,
		&"saw_stag_beetle": BugData.Habitat.TREE,
		&"ladybug": BugData.Habitat.FLOWER,
		&"mantis": BugData.Habitat.FLOWER,
		&"snail": BugData.Habitat.RAIN_FLOWER,
		&"firefly": BugData.Habitat.NEAR_WATER,
		&"cockroach": BugData.Habitat.FLOWER,
		&"mole_cricket": BugData.Habitat.UNDERGROUND,
		&"pond_skater": BugData.Habitat.WATER,
		&"bagworm": BugData.Habitat.TREE,
		&"pill_bug": BugData.Habitat.ROCK,
		&"spider": BugData.Habitat.TREE,
		&"ant": BugData.Habitat.GROUND,
		&"mosquito": BugData.Habitat.FLYING,
	}
	for id: StringName in habs:
		var bug: BugData = BugCatalog.get_bug(id)
		assert_that(bug).append_failure_message("missing %s" % id).is_not_null()
		var a := BugActor.create(bug, habs[id], Vector3(8.0, 0.4, 8.0), _rng)
		var s := BugActor.Sense.new()
		var origin: Vector3 = a.position
		for i in 300:
			s.player_position = a.position + Vector3(sin(i * 0.11) * 1.5, 0.0, cos(i * 0.11) * 1.5)
			s.player_move_gx = 3.0
			a.frame(s)
			if a.finished:
				break
		assert_bool(is_nan(a.pos.x) or is_nan(a.pos.y) or is_nan(a.pos.z)) \
			.append_failure_message("%s went NaN" % id).is_false()
		if not a.finished and a.action in [0, 1]:
			continue  ## scared / escaping — allowed to leave
		if not a.finished:
			assert_float(a.position.distance_to(origin)) \
				.append_failure_message("%s at %s (act %d)" % [id, a.position, a.action]).is_less(30.0)


func test_mole_cricket_pops_out_when_its_cell_is_dug() -> void:
	var a := _make(&"mole_cricket", BugData.Habitat.UNDERGROUND, Vector3(6.0, 0.0, 6.0))
	assert_int(a.action).is_equal(BugKera.HIDE)
	assert_bool(a.drawn).is_false()
	var s := BugActor.Sense.new()
	s.player_position = Vector3(6.0, 0.0, 6.5)
	s.player_action = BugActor.PlAct.DIG_SCOOP
	a.frame(s)
	assert_int(a.action).is_equal(BugKera.APPEAR)
	assert_bool(a.drawn).is_true()
	s.player_action = BugActor.PlAct.NONE
	_run(a, 60, s)
	assert_int(a.action).is_equal(BugKera.AVOID)
	assert_bool(a.finished).is_false()


func test_bagworm_hides_until_the_tree_is_shaken() -> void:
	var a := _make(&"bagworm", BugData.Habitat.TREE, Vector3(9.0, 0.0, 13.0))
	assert_int(a.action).is_equal(BugMino.HIDE)
	assert_bool(a.drawn).is_false()
	var s := BugActor.Sense.new()
	s.player_action = BugActor.PlAct.SHAKE_TREE
	a.frame(s)
	assert_int(a.action).is_equal(BugMino.APPEAR)
	assert_bool(a.drawn).is_true()


func test_pill_bug_curls_into_a_ball_when_scared() -> void:
	var a := _make(&"pill_bug", BugData.Habitat.ROCK, Vector3(5.0, 0.0, 5.0))
	var s := BugActor.Sense.new()
	s.player_action = BugActor.PlAct.REFLECT_SCOOP
	a.frame(s)
	assert_int(a.action).is_equal(BugDango.APPEAR)
	s.player_action = BugActor.PlAct.NONE
	_run(a, 30, s)
	a.patience = 30.0
	_run(a, 5, s)
	assert_int(a.action).is_equal(BugDango.AVOID)
	a.patience = 95.0
	s.net_swing_active = true
	s.net_swing_origin = a.position
	a.frame(s)
	assert_int(a.action).is_equal(BugDango.STOP)


func test_mosquito_homes_and_bites_then_leaves() -> void:
	var a := _make(&"mosquito", BugData.Habitat.FLYING, Vector3(4.0, 1.5, 4.0))
	assert_int(a.action).is_equal(BugKa.FLY)
	var s := BugActor.Sense.new()
	var bit := false
	for i in 600:
		s.player_position = a.position + Vector3(0.15, 0.0, 0.15)
		a.frame(s)
		if a.flag == BugKa.BIT:
			bit = true
			break
	assert_bool(bit).is_true()
