class_name TestVillagerOutdoor
extends GdUnitTestSuite

## `VillagerOutdoor` against `aNPC_think_chk_interrupt_proc` / `aNPC_ctrl_umbrella` /
## `aNPC_act_chase_insect` (`ac_npc_think.c_inc`, `ac_npc_ctrl.c_inc`).


func before_test() -> void:
	VillagerOutdoor.reset()


func test_one_umbrella_opens_per_window() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var a := RefCounted.new()
	var b := RefCounted.new()
	assert_bool(VillagerOutdoor.claim_umbrella(a, 10.0, rng)).is_true()
	## Someone else has to wait out the 0.5–1 s window.
	assert_bool(VillagerOutdoor.claim_umbrella(b, 10.2, rng)).is_false()
	assert_bool(VillagerOutdoor.claim_umbrella(b, 11.01, rng)).is_true()
	## Finishing the open restarts the window from then.
	VillagerOutdoor.release_umbrella(b, 11.5, rng)
	assert_bool(VillagerOutdoor.claim_umbrella(a, 11.9, rng)).is_false()
	assert_bool(VillagerOutdoor.claim_umbrella(a, 12.6, rng)).is_true()


func test_umbrella_visual_is_the_npc_def_list_tool() -> void:
	var v := VillagerData.new()
	v.default_umbrella = 3
	assert_that(VillagerOutdoor.umbrella_visual(v, null)).is_equal(&"tol_umb_04")
	v.default_umbrella = -1
	assert_that(VillagerOutdoor.umbrella_visual(v, null)).is_equal(&"")


func test_clap_needs_the_player_close_and_in_front() -> void:
	var npc := Vector3.ZERO
	## Facing +Z (yaw 0); player 4 m ahead.
	assert_bool(VillagerOutdoor.wants_clap(npc, 0.0, Vector3(0, 0, 4), true, true)).is_true()
	assert_bool(VillagerOutdoor.wants_clap(npc, 0.0, Vector3(0, 0, 4), false, true)).is_false()
	assert_bool(VillagerOutdoor.wants_clap(npc, 0.0, Vector3(0, 0, 4), true, false)).is_false()
	## 6 m is three units: out of range.
	assert_bool(VillagerOutdoor.wants_clap(npc, 0.0, Vector3(0, 0, 6.5), true, true)).is_false()
	## Behind them.
	assert_bool(VillagerOutdoor.wants_clap(npc, 0.0, Vector3(0, 0, -3), true, true)).is_false()
	## 60° off to the side is still in the cone.
	assert_bool(VillagerOutdoor.wants_clap(npc, 0.0, Vector3(sin(deg_to_rad(60)), 0, cos(deg_to_rad(60))) * 3.0, true, true)).is_true()


func test_a_fish_shadow_anywhere_hides_the_bugs() -> void:
	var fish := RefCounted.new()
	var bug := RefCounted.new()
	var found: Dictionary = VillagerOutdoor.chase_target(Vector3.ZERO, [[fish, Vector3(0, 0, 6)]], [[bug, Vector3(0, 0, 2)]])
	assert_that(found["target"]).is_equal(fish)
	assert_bool(found["fish"]).is_true()
	## Too far away, and the bug next to them is still ignored (`else if`).
	assert_bool(VillagerOutdoor.chase_target(Vector3.ZERO, [[fish, Vector3(0, 0, 20)]], [[bug, Vector3(0, 0, 2)]]).is_empty()).is_true()
	found = VillagerOutdoor.chase_target(Vector3.ZERO, [], [[bug, Vector3(0, 0, 4.5)]])
	assert_that(found["target"]).is_equal(bug)
	assert_bool(VillagerOutdoor.chase_target(Vector3.ZERO, [], [[bug, Vector3(0, 0, 5.5)]]).is_empty()).is_true()


func test_chase_steps_by_distance_and_angle() -> void:
	var S := VillagerOutdoor.ChaseStep
	assert_int(VillagerOutdoor.chase_step(Vector3.ZERO, 0.0, Vector3(0, 0, 3), false)).is_equal(S.WAIT)
	assert_int(VillagerOutdoor.chase_step(Vector3.ZERO, 0.0, Vector3(3, 0, 0), false)).is_equal(S.TURN)
	assert_int(VillagerOutdoor.chase_step(Vector3.ZERO, 0.0, Vector3(0, 0, 5), false)).is_equal(S.WALK)
	assert_int(VillagerOutdoor.chase_step(Vector3.ZERO, 0.0, Vector3(0, 0, 7), false)).is_equal(S.RUN)
	assert_int(VillagerOutdoor.chase_step(Vector3.ZERO, 0.0, Vector3(0, 0, 4), true)).is_equal(S.WAIT)
	assert_int(VillagerOutdoor.chase_step(Vector3.ZERO, 0.0, Vector3(0, 0, 9), true)).is_equal(S.WALK)
