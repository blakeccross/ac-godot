class_name TestNetSwing
extends GdUnitTestSuite

## `NetSwing` against the decomp's frame counts: `m_player_main_ready_net`, `ready_walk_net`,
## `slip_net`, `swing_net` and `stop_net`.

const GX := FieldCatalog.GX_TO_METERS


class _Target extends RefCounted:
	pass


func _ready_swing() -> NetSwing:
	var net := NetSwing.new()
	net.begin(false, 0.0, 0.0)
	return net


## Releases A and returns the swing on its first tick.
func _start_swing(net: NetSwing) -> void:
	net.tick(false, 0.0, 0.0, false)
	assert_int(net.state).is_equal(NetSwing.State.SWING)


func _probe_with(target: Object, at: Vector3, range_gx: float) -> NetSwing.Probe:
	var probe := NetSwing.Probe.new()
	probe.net_pos = Vector3.ZERO
	probe.candidates = [NetSwing.Candidate.new(target, at, range_gx)]
	return probe


func test_a_raises_the_net_and_release_swings() -> void:
	var net := _ready_swing()
	assert_int(net.state).is_equal(NetSwing.State.READY)
	## Holding A keeps it raised.
	for i: int in 30:
		net.tick(true, 0.0, 0.0, false)
	assert_int(net.state).is_equal(NetSwing.State.READY)
	net.tick(false, 0.0, 0.0, false)
	assert_int(net.state).is_equal(NetSwing.State.SWING)
	assert_bool(&"furi" in net.events).is_true()
	assert_float(net.frame).is_equal(1.0)


func test_empty_swing_runs_nineteen_ticks_then_stops() -> void:
	## `NET_SWING1` is 10 keyframes at 0.5 a tick: keyframe 10 is reached on the 18th tick,
	## and `CulcAnimation_Base2` reports the end one tick later.
	var net := _ready_swing()
	_start_swing(net)
	var ticks: int = 0
	while net.state == NetSwing.State.SWING:
		net.tick(true, 0.0, 0.0, false, NetSwing.Probe.new())
		ticks += 1
	assert_int(ticks).is_equal(19)
	assert_int(net.state).is_equal(NetSwing.State.STOP)
	assert_bool(&"stop_net" in net.events).is_true()
	assert_bool(&"hit" in net.events).is_false()


func test_stop_returns_to_wait_when_swing_wait_ends() -> void:
	## `SWING_WAIT1` is 21 keyframes: stopped on the 40th tick.
	var net := _ready_swing()
	_start_swing(net)
	while net.state == NetSwing.State.SWING:
		net.tick(true, 0.0, 0.0, false, NetSwing.Probe.new())
	var ticks: int = 0
	while net.state == NetSwing.State.STOP:
		net.tick(true, 0.0, 0.0, false)
		ticks += 1
	assert_int(ticks).is_equal(40)
	assert_int(net.state).is_equal(NetSwing.State.NONE)


func test_catch_check_opens_after_keyframe_six() -> void:
	## `current_frame > 6` first holds on the swing's 12th tick (keyframe 6.5).
	var net := _ready_swing()
	_start_swing(net)
	var target := _Target.new()
	var caught_on: int = -1
	var ticks: int = 0
	while net.state == NetSwing.State.SWING:
		net.tick(true, 0.0, 0.0, false, _probe_with(target, Vector3(0.0, 0.0, 0.1), 24.0))
		if net.caught != null and caught_on < 0:
			caught_on = ticks
			assert_bool(&"get" in net.events).is_true()
		ticks += 1
	assert_int(caught_on).is_equal(11)
	## The swing still plays out before the pull.
	assert_int(ticks).is_equal(19)
	assert_int(net.state).is_equal(NetSwing.State.PULL)
	assert_object(net.caught).is_same(target)
	## `swing_timer` gained 0.5 on each of the eight checked ticks.
	assert_float(net.swing_timer).is_equal(4.0)


func test_catch_sphere_is_net_reach_plus_insect_range() -> void:
	## 15 GX of net plus the insect's registered range.
	assert_bool(NetSwing.in_reach(Vector3.ZERO, Vector3(0.0, 0.0, 38.9 * GX), 24.0)).is_true()
	assert_bool(NetSwing.in_reach(Vector3.ZERO, Vector3(0.0, 0.0, 39.1 * GX), 24.0)).is_false()
	assert_bool(NetSwing.in_reach(Vector3.ZERO, Vector3(0.0, 22.9 * GX, 0.0), 8.0)).is_true()
	assert_bool(NetSwing.in_reach(Vector3.ZERO, Vector3(0.0, 23.1 * GX, 0.0), 8.0)).is_false()


func test_net_out_of_reach_catches_nothing() -> void:
	var net := _ready_swing()
	_start_swing(net)
	var target := _Target.new()
	while net.state == NetSwing.State.SWING:
		net.tick(true, 0.0, 0.0, false, _probe_with(target, Vector3(0.0, 0.0, 40.0 * GX), 24.0))
	assert_object(net.caught).is_null()
	assert_int(net.state).is_equal(NetSwing.State.STOP)


func test_wall_cuts_the_swing_short_after_keyframe_six() -> void:
	var net := _ready_swing()
	_start_swing(net)
	var probe := NetSwing.Probe.new()
	probe.line_bits = NetSwing.LINE_WALL
	var ticks: int = 0
	while net.state == NetSwing.State.SWING:
		net.tick(true, 0.0, 0.0, false, probe)
		ticks += 1
	## Ignored until keyframe 6.5 (the 12th tick), which then stops with `AMI_HIT`.
	assert_int(ticks).is_equal(12)
	assert_int(net.state).is_equal(NetSwing.State.STOP)
	assert_bool(&"hit" in net.events).is_true()
	## `CulcAnimation_Swing_net` stepped back half a keyframe instead of forward.
	assert_float(net.frame).is_equal(6.0)


func test_water_only_splashes() -> void:
	var net := _ready_swing()
	_start_swing(net)
	var probe := NetSwing.Probe.new()
	probe.line_bits = NetSwing.LINE_UNDERWATER
	var splashed: bool = false
	while net.state == NetSwing.State.SWING:
		net.tick(true, 0.0, 0.0, false, probe)
		splashed = splashed or &"splash" in net.events
	assert_bool(splashed).is_true()
	assert_bool(&"hit" in net.events).is_false()


func test_villager_hit_is_reported_for_uzai() -> void:
	var net := _ready_swing()
	_start_swing(net)
	var npc := _Target.new()
	var probe := NetSwing.Probe.new()
	probe.hit_actor = npc
	while net.state == NetSwing.State.SWING:
		net.tick(true, 0.0, 0.0, false, probe)
	assert_int(net.state).is_equal(NetSwing.State.STOP)
	assert_object(net.hit_actor).is_same(npc)


func test_hit_after_a_catch_pulls_with_ami_hit() -> void:
	var net := _ready_swing()
	_start_swing(net)
	var target := _Target.new()
	## Catch on keyframe 6.5, strike a wall on the next tick.
	for i: int in 12:
		net.tick(true, 0.0, 0.0, false, _probe_with(target, Vector3.ZERO, 24.0))
	assert_object(net.caught).is_same(target)
	var probe := NetSwing.Probe.new()
	probe.line_bits = NetSwing.LINE_GROUND
	net.tick(true, 0.0, 0.0, false, probe)
	assert_int(net.state).is_equal(NetSwing.State.PULL)
	assert_bool(&"hit" in net.events).is_true()


func test_ready_walk_accelerates_to_the_creep_cap() -> void:
	var net := _ready_swing()
	net.tick(true, 1.0, 0.0, true)
	assert_int(net.state).is_equal(NetSwing.State.READY_WALK)
	net.tick(true, 1.0, 0.0, true)
	assert_float(net.speed_gx).is_equal_approx(NetSwing.WALK_ACCEL, 0.0001)
	for i: int in 10:
		net.tick(true, 1.0, 0.0, true)
	## 1.8 GX a frame at full stick (walking is 4.875).
	assert_float(net.speed_gx).is_equal_approx(NetSwing.WALK_MAX_GX, 0.0001)
	## `0.252 * sqrt(speed / 1.8)`.
	assert_float(net.frame_speed).is_equal_approx(0.252, 0.0001)
	## Let go of the stick: decelerate 0.32625 a tick, then settle back into READY.
	var ticks: int = 0
	while net.state == NetSwing.State.READY_WALK:
		net.tick(true, 0.0, 0.0, false)
		ticks += 1
	assert_int(ticks).is_equal(int(ceil(NetSwing.WALK_MAX_GX / NetSwing.WALK_DECEL)))
	assert_int(net.state).is_equal(NetSwing.State.READY)


func test_ready_walk_anim_rate_has_a_floor() -> void:
	var net := _ready_swing()
	net.tick(true, 0.2, 0.0, true)
	net.tick(true, 0.2, 0.0, true)
	assert_float(net.frame_speed).is_equal_approx(NetSwing.WALK_ANIM_MIN, 0.0001)


func test_release_while_walking_swings() -> void:
	var net := _ready_swing()
	net.tick(true, 1.0, 0.0, true)
	net.tick(true, 1.0, 0.0, true)
	net.tick(false, 1.0, 0.0, true)
	assert_int(net.state).is_equal(NetSwing.State.SWING)


func test_dash_skids_then_readies() -> void:
	var net := NetSwing.new()
	net.begin(true, PlayerLocomotion.ORIG_RUN, 0.0)
	assert_int(net.state).is_equal(NetSwing.State.SLIP)
	assert_bool(&"slip" in net.events).is_true()
	var ticks: int = 0
	while net.state == NetSwing.State.SLIP:
		net.tick(true, 0.0, 0.0, false)
		ticks += 1
	assert_int(ticks).is_equal(int(ceil(PlayerLocomotion.ORIG_RUN / NetSwing.SLIP_BRAKE)))
	assert_int(net.state).is_equal(NetSwing.State.READY)


func test_release_during_skid_swings() -> void:
	var net := NetSwing.new()
	net.begin(true, PlayerLocomotion.ORIG_RUN, 0.0)
	net.tick(false, 0.0, 0.0, false)
	assert_int(net.state).is_equal(NetSwing.State.SWING)


func test_net_point_follows_the_hand() -> void:
	## `Matrix_rotateXYZ(0, 3000, 0)` then 4000 model units down Z, ×0.01 → 40 GX.
	var p: Vector3 = NetSwing.net_point(Transform3D.IDENTITY, NetSwing.NET_POS_GX)
	var yaw: float = MLib.s16_to_rad(NetSwing.NET_YAW_S16)
	var want := Vector3(sin(yaw), 0.0, cos(yaw)) * (40.0 * GX)
	assert_vector(p).is_equal_approx(want, Vector3.ONE * 0.0001)
	var moved := Transform3D(Basis(Vector3.UP, PI), Vector3(1.0, 2.0, 3.0))
	var q: Vector3 = NetSwing.net_point(moved, NetSwing.NET_POS_GX)
	assert_vector(q).is_equal_approx(Vector3(1.0, 2.0, 3.0) - want, Vector3.ONE * 0.0001)


func test_a_forced_target_is_taken_by_a_swing_under_way() -> void:
	## `Set_Item_net_catch_request_force_proc` (the bee swarm): the second checked tick, out
	## of reach or not.
	var net := _ready_swing()
	_start_swing(net)
	var target := _Target.new()
	var caught_on: int = -1
	var ticks: int = 0
	while net.state == NetSwing.State.SWING:
		var probe := _probe_with(target, Vector3(0.0, 0.0, 200.0 * GX), 24.0)
		probe.forced = target
		net.tick(true, 0.0, 0.0, false, probe)
		if net.caught != null and caught_on < 0:
			caught_on = ticks
		ticks += 1
	assert_int(caught_on).is_equal(12)
	assert_object(net.caught).is_same(target)


func test_the_bee_swarm_is_netted_as_a_bee() -> void:
	var swarm := BeeSwarm.new()
	add_child(swarm)
	assert_bool(swarm.netable()).is_false()
	swarm.phase = BeeSwarm.Phase.FLY
	assert_bool(swarm.netable()).is_false()
	## Two seconds of chasing (`catch_delay_frames` 60).
	swarm.set("_fly_time", 2.0)
	assert_bool(swarm.netable()).is_true()
	var catch_: Netting.Catch = Netting.begin_catch(swarm)
	assert_object(catch_).is_not_null()
	assert_str(String(catch_.bug.id)).is_equal("bee")
	assert_int(swarm.phase).is_equal(BeeSwarm.Phase.DISAPPEAR)
	swarm.queue_free()


func test_the_swing_effect_fires_once_as_the_net_comes_down() -> void:
	var net := NetSwing.new()
	net.begin(false, 0.0, 0.0)
	net._begin_swing()
	var fired: int = 0
	for i: int in 20:
		net.events.clear()
		net._tick_swing(NetSwing.Probe.new())
		fired += net.events.count(&"swing_fx")
		if net.state != NetSwing.State.SWING:
			break
	assert_int(fired).is_equal(1)
