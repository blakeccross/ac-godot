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


## A 32×32-unit (2×2 acre) flat field with an empty layout, for FG / unit queries.
func _field_sense() -> BugActor.Sense:
	var s := BugActor.Sense.new()
	s.grid = WorldGrid.new()
	s.grid.configure(32, 32, 2.0, Vector3.ZERO)
	s.layout = WorldData.new()
	s.layout.columns = 32
	s.layout.rows = 32
	return s


func _put(layout: WorldData, kind: StringName, cell: Vector2i, visual: StringName = &"") -> ObjectPlacement:
	var o := ObjectPlacement.new()
	o.kind = kind
	o.cell = cell
	o.visual_id = visual
	o.id = StringName("%s_%d_%d" % [kind, cell.x, cell.y])
	layout.objects.append(o)
	return o


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
	## `aICH_check_block_edge`: the outer ring of units (in-block 0 / 15) is off limits.
	## Without a grid the acre spans −320..320 GX, so x = 300 GX is unit 15.
	var b := _make(&"common_butterfly", BugData.Habitat.FLYING, Vector3(4.0, 0.5, 4.0))
	b.pos = Vector3(300.0, b.pos.y, b.home.z)
	b.frame(BugActor.Sense.new())
	assert_int(b.action).is_equal(BugChou.LET_ESCAPE)
	assert_int(b.alpha_time).is_equal(0x50)
	_run(b, 90, BugActor.Sense.new())
	assert_bool(b.finished).is_true()


func test_butterfly_far_from_home_but_inside_the_acre_keeps_flying() -> void:
	var b := _make(&"common_butterfly", BugData.Habitat.FLYING, Vector3(4.0, 0.5, 4.0))
	b.pos = Vector3(-250.0, b.pos.y, 250.0)  ## unit 1 / 14 — the inner edge
	b.frame(BugActor.Sense.new())
	assert_int(b.action).is_equal(BugChou.FLY)


func test_butterfly_lands_on_a_white_pansy_after_its_cooldown() -> void:
	## `aICH_rest_check`: `f32_work3` counts 120 → 0 by 0.5 a frame, then a
	## `FLOWER_PANSIES0` unit below lands it; HOVER 10 frames, REST 15–45, FLY again.
	var s := _field_sense()
	var cell := Vector2i(5, 5)
	_put(s.layout, &"flower", cell, &"FLOWER_PANSIES0")
	var at: Vector3 = s.grid.cell_to_world(cell)
	var b := _make(&"common_butterfly", BugData.Habitat.FLOWER, at)
	var seen := {}
	for _i: int in 700:
		if b.action == BugChou.FLY:
			b.pos.x = at.x / BugActor.GX_M  ## hold it over the pansy
			b.pos.z = at.z / BugActor.GX_M
		b.frame(s)
		seen[b.action] = true
		if b.action == BugChou.REST:
			break
	assert_bool(seen.has(BugChou.LANDING)).is_true()
	assert_bool(seen.has(BugChou.HOVER)).is_true()
	assert_bool(seen.has(BugChou.REST)).is_true()
	assert_int(b.pose_index()).is_equal(1)


func test_butterfly_scared_by_a_dig_within_sixty_gx() -> void:
	var s := _field_sense()
	var b := _make(&"tiger_butterfly", BugData.Habitat.FLOWER, s.grid.cell_to_world(Vector2i(5, 5)))
	b._prog.setup_action(b, BugChou.HOVER)
	s.player_action = BugActor.PlAct.DIG_SCOOP
	s.player_action_cell = Vector2i(6, 5)  ## next unit: 40 GX away
	b.frame(s)
	assert_int(b.action).is_equal(BugChou.AVOID)


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
	var s := _tree_shaken_sense(Vector2i(4, 6))
	b.frame(s)
	assert_int(b.action).is_equal(BugKabuto.AVOID)
	assert_float(b.pitch).is_equal(0.0)
	_run(b, 40, s)
	assert_float(b.position.y).is_greater(start_y)


func _tree_shaken_sense(cell: Vector2i) -> BugActor.Sense:
	## `mPlib_Check_tree_shaken`: the player's shake table holds this unit's tree.
	var s := BugActor.Sense.new()
	s.grid = WorldGrid.new()
	s.grid.configure(12, 12, 2.0, Vector3.ZERO)
	s.shaken_cells[cell] = true
	return s


func test_beetle_ignores_a_tree_shake_in_another_unit() -> void:
	var b := _make(&"drone_beetle", BugData.Habitat.TREE, Vector3(9.0, 2.0, 13.0))
	var s := _tree_shaken_sense(Vector2i(8, 8))
	_run(b, 20, s)
	assert_int(b.action).is_not_equal(BugKabuto.AVOID)


func test_beetle_net_scare_range_is_angular() -> void:
	var b := _make(&"drone_beetle", BugData.Habitat.TREE, Vector3(9.0, 2.0, 13.0))
	## `aINS_get_catch_range_sub` compares `world.angle.y` with the angle from the beetle to
	## the player: the player must stand on the side the beetle faces.
	b.angle_y = 0.0
	## Beetle faces +Z; player 1 m in front of it → catchable (24 GX).
	assert_float(b.net_catch_range_gx(b.position + Vector3(0.0, 0.0, 1.0))).is_equal(24.0)
	## Player behind it (the far side of the trunk) → 0.
	assert_float(b.net_catch_range_gx(b.position + Vector3(0.0, 0.0, -1.0))).is_equal(0.0)
	assert_object(b.net_candidate(b.position + Vector3(0.0, 0.0, -1.0))).is_null()
	var row: NetSwing.Candidate = b.net_candidate(b.position + Vector3(0.0, 0.0, 1.0))
	assert_object(row.target).is_same(b)
	assert_float(row.range_gx).is_equal(24.0)


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
	s.player_position = Vector3(6.0, 0.0, 7.5)
	s.player_yaw = PI   ## facing north
	s.player_action = BugActor.PlAct.DIG_SCOOP
	## Digging the next unit over leaves it hidden; its own unit (6 m = 120 GX → 11) wakes it.
	s.player_action_cell = Vector2i(11, 12)
	a.frame(s)
	assert_int(a.action).is_equal(BugKera.HIDE)
	s.player_action_cell = Vector2i(11, 11)
	a.frame(s)
	assert_int(a.action).is_equal(BugKera.APPEAR)
	assert_float(absf(wrapf(a.angle_y - PI, -PI, PI))).is_less_equal(deg_to_rad(60.5))
	assert_bool(a.drawn).is_true()
	s.player_action = BugActor.PlAct.NONE
	_run(a, 60, s)
	assert_int(a.action).is_equal(BugKera.AVOID)
	assert_bool(a.finished).is_false()


func test_bagworm_hides_until_the_tree_is_shaken() -> void:
	var s := _field_sense()
	var tree := Vector2i(5, 5)
	_put(s.layout, &"tree", tree)
	var at: Vector3 = s.grid.cell_to_world(tree)
	var a := _make(&"bagworm", BugData.Habitat.TREE, at)
	assert_int(a.action).is_equal(BugMino.HIDE)
	assert_bool(a.drawn).is_false()
	assert_float(a.pos.y).is_equal_approx(65.0, 0.01)
	s.player_position = at + Vector3(-3.0, 0.0, 0.0)   ## west of the tree
	s.player_action = BugActor.PlAct.SHAKE_TREE
	s.player_action_cell = Vector2i(6, 5)
	a.frame(s)
	assert_int(a.action).is_equal(BugMino.HIDE)
	s.player_action_cell = tree
	a.frame(s)
	assert_int(a.action).is_equal(BugMino.APPEAR)
	assert_bool(a.drawn).is_true()
	## Drops on the far (east) side, 18 GX north.
	assert_float(a.pos.x - a.home.x).is_equal_approx(30.0, 0.01)
	s.player_action = BugActor.PlAct.NONE
	for i in 300:
		a.frame(s)
		if a.action == BugMino.WAIT:
			break
	assert_int(a.action).is_equal(BugMino.WAIT)
	var hang := Vector3(a.pos)
	## A second shake swings it on its 50 GX arm, then it settles facing south again.
	s.player_action = BugActor.PlAct.SHAKE_TREE
	a.frame(s)
	s.player_action = BugActor.PlAct.NONE
	var swung := 0.0
	for i in 400:
		a.frame(s)
		swung = maxf(swung, absf(a.pos.x - hang.x))
	assert_float(swung).is_greater(0.5)
	assert_float(absf(wrapf(a.rot.y - PI, -PI, PI))).is_less(0.01)
	## After its 1200 frames it climbs back into the tree.
	for i in 1200:
		a.frame(s)
		if a.action == BugMino.HIDE:
			break
	assert_int(a.action).is_equal(BugMino.HIDE)


func test_bagworm_falls_from_a_felled_tree_and_crawls_off() -> void:
	var s := _field_sense()
	var tree := Vector2i(5, 5)
	var t := _put(s.layout, &"tree", tree)
	var at: Vector3 = s.grid.cell_to_world(tree)
	var a := _make(&"bagworm", BugData.Habitat.TREE, at)
	a.frame(s)
	assert_int(a.action).is_equal(BugMino.HIDE)
	s.layout.objects.erase(t)
	s.player_position = at + Vector3(0.0, 0.0, 6.0)
	s.player_yaw = PI
	a.frame(s)
	assert_int(a.action).is_equal(BugMino.FALL)
	for i in 60:
		a.frame(s)
		if a.action == BugMino.LET_ESCAPE:
			break
	assert_int(a.action).is_equal(BugMino.LET_ESCAPE)
	assert_float(absf(wrapf(a.angle_y - PI, -PI, PI))).is_less_equal(deg_to_rad(60.5))


func test_pill_bug_curls_into_a_ball_when_scared() -> void:
	var s := _field_sense()
	var rock := Vector2i(5, 5)
	var at: Vector3 = s.grid.cell_to_world(rock)
	var a := _make(&"pill_bug", BugData.Habitat.ROCK, at)
	(a._prog as BugDango).set_rock_cell(rock)
	s.player_position = at + Vector3(0.0, 0.0, 10.0)  ## outside the 120 GX stress radius
	s.player_yaw = PI
	## A strike on a neighbouring unit does nothing.
	s.player_action = BugActor.PlAct.REFLECT_SCOOP
	s.player_action_cell = Vector2i(5, 6)
	a.frame(s)
	assert_int(a.action).is_equal(BugDango.HIDE)
	s.player_action_cell = rock
	a.frame(s)
	assert_int(a.action).is_equal(BugDango.APPEAR)
	s.player_action = BugActor.PlAct.NONE
	s.player_action_cell = Vector2i(-1, -1)
	_run(a, 30, s)
	a.patience = 30.0
	_run(a, 2, s)
	assert_int(a.action).is_equal(BugDango.AVOID)
	## Scares count only once it has crawled off the rock's unit (`bg_type` 4 → 2).
	for i in 120:
		a.frame(s)
		if a.bg_type == 2:
			break
	assert_int(a.bg_type).is_equal(2)
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


func test_cicada_flees_a_shaken_tree_in_its_unit() -> void:
	var calm := _make(&"robust_cicada", BugData.Habitat.TREE, Vector3(9.0, 2.0, 13.0))
	var scared := _make(&"robust_cicada", BugData.Habitat.TREE, Vector3(9.0, 2.0, 13.0))
	var quiet := BugActor.Sense.new()
	calm.frame(quiet)
	scared.frame(quiet)
	assert_int(scared.action).is_equal(calm.action)
	calm.frame(quiet)
	scared.frame(_tree_shaken_sense(Vector2i(4, 6)))
	assert_int(calm.action).is_not_equal(BugSemi.AVOID)
	assert_int(scared.action).is_equal(BugSemi.AVOID)


# ---- shared framework (`ac_insect_move.c_inc`) --------------------------

func test_stress_radius_is_three_forty_gx_units_plus_type_bias() -> void:
	## `aINS_MAX_STRESS_DIST` = 3 × `mFI_UNIT_BASE_SIZE_F` (40 GX) + `catch_ME_data[type]`.
	var butterfly := _make(&"common_butterfly", BugData.Habitat.FLYING, Vector3.ZERO)
	var cricket := _make(&"cricket", BugData.Habitat.GROUND, Vector3.ZERO)
	var cicada := _make(&"robust_cicada", BugData.Habitat.TREE, Vector3.ZERO)
	assert_float(butterfly.stress_radius_gx()).is_equal(120.0)
	assert_float(cricket.stress_radius_gx()).is_equal(100.0)
	assert_float(cicada.stress_radius_gx()).is_equal(130.0)


func test_player_walking_two_and_a_half_units_away_stresses_an_insect() -> void:
	## 100 GX (5 m) is inside the 120 GX radius: `idx = (int)(80 − 60) / 20 = 1` → ×1.0.
	var b := _make(&"tiger_butterfly", BugData.Habitat.FLYING, Vector3(0.0, 1.5, 0.0))
	var s := BugActor.Sense.new()
	for i: int in 10:
		s.player_position = b.position + Vector3(5.0, 0.0, 0.1 * i)
		b.frame(s)
	assert_float(b.patience).is_greater(0.0)



# ---- TONBO (dragonfly) ---------------------------------------------

func test_dragonfly_cruises_at_its_hover_height_and_stops_to_turn() -> void:
	## `aITB_height_ctrl`: 52–62 GX over the ground; bursts of 20 frames then a WAIT turn.
	var a := _make(&"common_dragonfly", BugData.Habitat.FLYING, Vector3(0.0, 0.0, 0.0))
	var s := BugActor.Sense.new()
	var waited := false
	for _i: int in 600:
		a.frame(s)
		if a.action == BugTonbo.WAIT:
			waited = true
	assert_bool(waited).is_true()
	assert_float(a.pos.y).is_between(40.0, 75.0)
	assert_float(a.f32_work[0]).is_between(52.0, 62.0)


func test_dragonfly_turns_back_toward_the_acre_centre_past_240_gx() -> void:
	## `aITB_wait_init`: beyond `6 × 40` GX from the acre centre the new heading is the centre.
	var a := _make(&"common_dragonfly", BugData.Habitat.FLYING, Vector3(0.0, 0.0, 0.0))
	a.pos = Vector3(260.0, 60.0, 0.0)
	a.angle_y = PI * 0.5  ## heading east, away from the centre
	a._prog.setup_action(a, BugTonbo.WAIT)
	assert_float(absf(angle_difference(a.angle_y, -PI * 0.5))).is_less(0.01)


func test_banded_dragonfly_leaves_past_480_gx() -> void:
	var a := _make(&"banded_dragonfly", BugData.Habitat.FLYING, Vector3(0.0, 0.0, 0.0))
	assert_int(a.action).is_equal(BugTonbo.ONIYANMA_FLY)
	a.pos = Vector3(300.0, 60.0, 300.0)  ## 424 GX out: still patrolling
	a.frame(BugActor.Sense.new())
	assert_int(a.action).is_equal(BugTonbo.ONIYANMA_FLY)
	a.pos = Vector3(360.0, 60.0, 360.0)  ## 509 GX out
	a.frame(BugActor.Sense.new())
	assert_int(a.action).is_equal(BugTonbo.LET_ESCAPE)


func test_red_dragonfly_perches_on_a_reserved_unit() -> void:
	var s := _field_sense()
	_put(s.layout, &"reserve", Vector2i(5, 5), &"SIGNBOARD")
	var at: Vector3 = s.grid.cell_to_world(Vector2i(5, 5))
	var a := _make(&"red_dragonfly", BugData.Habitat.FLYING, at)
	var seen := {}
	for _i: int in 400:
		a.frame(s)
		seen[a.action] = true
		if a.action == BugTonbo.REST_ON_NOTICE:
			break
	assert_bool(seen.has(BugTonbo.FLY_ON_NOTICE)).is_true()
	assert_int(a.action).is_equal(BugTonbo.REST_ON_NOTICE)
	assert_float(a.pos.y).is_equal_approx(20.0, 3.0)


# ---- SEMI / KABUTO / GOKI on trunks -------------------------------------

func test_trunk_insect_on_a_cedar_sits_lower_and_further_south() -> void:
	## `init_posY` / `init_posZ` = {35, 30} / {−2, 8} for {tree, CEDAR_TREE}.
	var s := _field_sense()
	_put(s.layout, &"tree", Vector2i(4, 4), &"TREE")
	_put(s.layout, &"tree", Vector2i(8, 4), &"CEDAR_TREE")
	var oak := _make(&"drone_beetle", BugData.Habitat.TREE, s.grid.cell_to_world(Vector2i(4, 4)))
	var cedar := _make(&"drone_beetle", BugData.Habitat.TREE, s.grid.cell_to_world(Vector2i(8, 4)))
	var base_z: float = s.grid.cell_to_world(Vector2i(4, 4)).z / BugActor.GX_M
	oak.frame(s)
	cedar.frame(s)
	assert_float(oak.pos.y).is_equal_approx(35.0, 0.01)
	assert_float(oak.pos.z - base_z).is_equal_approx(-2.0, 0.01)
	assert_float(cedar.pos.y).is_equal_approx(30.0, 0.01)
	assert_float(cedar.pos.z - base_z).is_equal_approx(8.0, 0.01)


func test_swaying_beetle_is_still_netted_from_the_south() -> void:
	## Only `shape_info.rotation.y` sways; `world.angle.y` keeps 0, which the catch-range
	## facing test uses — the player nets it from the south (camera) side of the trunk.
	var b := _make(&"drone_beetle", BugData.Habitat.TREE, Vector3(9.0, 0.0, 13.0))
	_run(b, 200, BugActor.Sense.new())
	assert_float(b.net_catch_range_gx(b.position + Vector3(0.0, 0.0, 1.0))).is_equal(24.0)
	assert_float(b.net_catch_range_gx(b.position + Vector3(0.0, 0.0, -1.0))).is_equal(0.0)


func test_scared_beetle_flies_off_the_way_the_player_faces() -> void:
	var b := _make(&"drone_beetle", BugData.Habitat.TREE, Vector3(9.0, 2.0, 13.0))
	var s := _tree_shaken_sense(Vector2i(4, 6))
	s.player_position = b.position + Vector3(0.0, 0.0, 1.0)
	s.player_yaw = PI  ## facing the trunk (north)
	b.frame(s)
	assert_int(b.action).is_equal(BugKabuto.AVOID)
	assert_float(absf(angle_difference(b.angle_y, PI))).is_less_equal(deg_to_rad(60.5))


func test_cicada_ignores_a_dig_forty_gx_away_but_not_twenty() -> void:
	## `aISM_SCOOP_SCARE_DIST` 30 GX.
	var s := _field_sense()
	var cell := Vector2i(6, 6)
	var c := _make(&"robust_cicada", BugData.Habitat.TREE, s.grid.cell_to_world(cell))
	c.frame(s)
	s.player_action = BugActor.PlAct.DIG_SCOOP
	s.player_action_cell = cell + Vector2i(1, 0)
	c.frame(s)
	assert_int(c.action).is_equal(BugSemi.WAIT)
	s.player_action_cell = cell
	c.frame(s)
	assert_int(c.action).is_equal(BugSemi.AVOID)


func test_beetle_scared_by_an_axe_hit_in_its_acre_within_150_gx() -> void:
	## `mPlib_Check_VibUnit_OneFrame` (an axe hit in the same acre) and `player_distance_xz < 150`.
	var s := _field_sense()
	var b := _make(&"drone_beetle", BugData.Habitat.TREE, s.grid.cell_to_world(Vector2i(6, 6)))
	b.frame(s)
	s.player_swung_tool = true
	s.player_position = b.position + Vector3(9.0, 0.0, 0.0)  ## 180 GX east
	b.frame(s)
	assert_int(b.action).is_equal(BugKabuto.WAIT)
	s.player_position = b.position + Vector3(6.0, 0.0, 0.0)  ## 120 GX east
	b.frame(s)
	assert_int(b.action).is_equal(BugKabuto.AVOID)


# ---- HOTARU (firefly) ----------------------------------------------

func test_firefly_hovers_seventy_gx_over_the_ground() -> void:
	## `GetBgY_OnlyCenter_FromWpos(pos, −70)`, bobbing ±10 GX (`aIHT_fuwafuwa`).
	var a := _make(&"firefly", BugData.Habitat.NEAR_WATER, Vector3(2.0, 0.0, 2.0))
	var lo := 1e9
	var hi := -1e9
	for _i: int in 600:
		a.frame(BugActor.Sense.new())
		lo = minf(lo, a.pos.y)
		hi = maxf(hi, a.pos.y)
	assert_float(lo).is_greater(55.0)
	assert_float(hi).is_less(85.0)


func test_stressed_firefly_veers_away_from_the_player() -> void:
	var a := _make(&"firefly", BugData.Habitat.NEAR_WATER, Vector3(0.0, 0.0, 0.0))
	a.f32_work[0] = a.pos.x + 100.0  ## a far target so the steering branch runs
	a.patience = 95.0
	var s := BugActor.Sense.new()
	s.player_position = a.position + Vector3(0.0, 0.0, 2.0)  ## player due south
	s.player_move_gx = 0.0
	for _i: int in 200:
		a.patience = 95.0
		a.frame(s)
	assert_int(a.flag).is_equal(1)
	## Target heading is `player_angle_y + 180°`, straight away from the player.
	var away: float = BugProgram.angle_to(s.player_position / BugActor.GX_M, a.pos)
	assert_float(absf(angle_difference(a.s32_work[1] * MLib.S16, away))).is_less(deg_to_rad(2.0))
	assert_float(a.player_distance_xz).is_greater(60.0)


func test_mosquito_hovers_inside_a_half_unit_and_ignores_other_acres() -> void:
	## 16 GX off (0.8 m): inside `mFI_UNIT_BASE_SIZE_F / 2` = 20 GX → ATTACK_WAIT.
	var near := _make(&"mosquito", BugData.Habitat.FLYING, Vector3(10.0, 0.0, 10.0))
	var s := _field_sense()
	var entered := false
	for i in 20:
		s.player_position = Vector3(near.position.x + 0.8, 0.0, near.position.z)
		near.frame(s)
		if near.action == BugKa.ATTACK_WAIT:
			entered = true
			break
	assert_bool(entered).is_true()
	## 3 m away but over the acre line (acres are 32 m): it keeps circling.
	var far := _make(&"mosquito", BugData.Habitat.FLYING, Vector3(30.5, 0.0, 10.0))
	var s2 := _field_sense()
	for i in 30:
		s2.player_position = Vector3(33.5, 0.0, far.position.z)
		far.frame(s2)
	assert_int(far.action).is_equal(BugKa.FLY)


func test_ladybug_sits_on_the_flower_head_and_flees_a_nearby_dig() -> void:
	var s := _field_sense()
	var at: Vector3 = s.grid.cell_to_world(Vector2i(5, 5))
	at.y = 0.0
	_put(s.layout, &"flower", Vector2i(5, 5))
	var a := _make(&"ladybug", BugData.Habitat.FLOWER, at)
	assert_float(a.pos.y).is_equal_approx(25.0, 0.01)
	## Not on a flower is no scare in the US build.
	var bare := _field_sense()
	var b := _make(&"ladybug", BugData.Habitat.FLOWER, at)
	_run(b, 30, bare)
	assert_int(b.action).is_not_equal(BugTentou.AVOID)
	## A dig two units off (80 GX) leaves it; one unit off (40 GX) is inside 60.
	s.player_position = at + Vector3(0.0, 0.0, 6.0)
	s.player_action = BugActor.PlAct.DIG_SCOOP
	s.player_action_cell = Vector2i(5, 7)
	a.frame(s)
	assert_int(a.action).is_not_equal(BugTentou.AVOID)
	s.player_action_cell = Vector2i(5, 6)
	a.frame(s)
	assert_int(a.action).is_equal(BugTentou.AVOID)


func test_snail_only_leaves_once_its_flower_is_gone() -> void:
	var s := _field_sense()
	var at: Vector3 = s.grid.cell_to_world(Vector2i(5, 5))
	at.y = 0.0
	var f := _put(s.layout, &"flower", Vector2i(5, 5))
	var a := _make(&"snail", BugData.Habitat.RAIN_FLOWER, at)
	s.player_position = at + Vector3(0.0, 0.0, 2.0)
	s.player_action = BugActor.PlAct.DIG_SCOOP
	s.player_action_cell = Vector2i(5, 6)
	_run(a, 10, s)
	assert_int(a.action).is_not_equal(BugTentou.AVOID_MAIMAI)
	s.layout.objects.erase(f)
	a.frame(s)
	assert_int(a.action).is_equal(BugTentou.AVOID_MAIMAI)


func test_pond_skater_never_skates_off_its_pond() -> void:
	var s := _field_sense()
	for x in range(4, 7):
		for z in range(4, 7):
			s.grid.set_terrain(Vector2i(x, z), WorldGrid.Terrain.WATER)
	var at: Vector3 = s.grid.cell_to_world(Vector2i(5, 5))
	var a := _make(&"pond_skater", BugData.Habitat.WATER, at)
	assert_float(a.pos.y).is_equal_approx(at.y / BugActor.GX_M + 14.0, 0.01)
	var moved := false
	for i in 900:
		a.frame(s)
		assert_bool(BugBg.water_at(s.grid, a.pos)) \
			.append_failure_message("left the pond at %s (frame %d)" % [a.pos, i]).is_true()
		if BugProgram.dist_xz(a.pos, a.home) > 5.0:
			moved = true
	assert_bool(moved).is_true()


func test_crawling_pill_bug_dives_into_water_ahead_and_drowns() -> void:
	var s := _field_sense()
	s.bg = BugBg.make_probe(s.grid, s.layout)
	s.ground = BugBg.make_ground(s.grid, s.layout)
	for z in 32:
		s.grid.set_terrain(Vector2i(7, z), WorldGrid.Terrain.WATER)
	var at: Vector3 = s.grid.cell_to_world(Vector2i(5, 5))
	var a := _make(&"ant", BugData.Habitat.GROUND, at)
	s.player_position = at + Vector3(-10.0, 0.0, 0.0)
	s.player_yaw = PI * 0.5   ## facing east, toward the water
	var dived := false
	for i in 400:
		a.frame(s)
		if a.action == BugDango.DIVE:
			dived = true
		if a.finished:
			break
	assert_bool(dived).is_true()
	assert_bool(a.finished).is_true()
