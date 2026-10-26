class_name TestHeldBalloon
extends GdUnitTestSuite

## `m_player_item_balloon`: the balloon's sway on its string.

const F := 1.0 / 30.0


func test_it_turns_back_and_forth_without_settling() -> void:
	var b := HeldBalloon.new()
	var lo: float = 0.0
	var hi: float = 0.0
	for i: int in 600:
		b.step(F, Vector3.ZERO, 0.0, false, 0.0)
		lo = minf(lo, b.angle_z)
		hi = maxf(hi, b.angle_z)
	assert_float(hi).is_greater(500.0)
	assert_float(lo).is_less(-500.0)
	assert_float(hi).is_less_equal(HeldBalloon.SWAY_LIMIT)


func test_it_trails_the_hand() -> void:
	var b := HeldBalloon.new()
	## Hand moving forward (+z facing south): the balloon leans back.
	for i: int in 30:
		b.step(F, Vector3(0.0, 0.0, 2.0) * PlayerLocomotion.GX_SPEED, 0.0, false, 0.0)
	assert_float(b.angle_x).is_less(0.0)
	## Stopped: it eases back toward upright.
	var leaning: float = absf(b.angle_x)
	for i: int in 30:
		b.step(F, Vector3.ZERO, 0.0, false, 0.0)
	assert_float(absf(b.angle_x)).is_less(leaning)


func test_it_bobs_while_walking() -> void:
	var b := HeldBalloon.new()
	var seen: float = 0.0
	for i: int in 60:
		b.step(F, Vector3.ZERO, 0.0, true, 3.0 * PlayerLocomotion.GX_SPEED)
		seen = maxf(seen, absf(b.add_rot_x))
	assert_float(seen).is_greater(100.0)
	var still := HeldBalloon.new()
	for i: int in 60:
		still.step(F, Vector3.ZERO, 0.0, false, 0.0)
	assert_float(still.add_rot_x).is_equal(0.0)


func test_the_twist_is_the_same_at_any_step() -> void:
	var fine := HeldBalloon.new()
	var coarse := HeldBalloon.new()
	for i: int in 240:
		fine.step(1.0 / 60.0, Vector3.ZERO, 0.0, false, 0.0)
	for i: int in 60:
		coarse.step(1.0 / 15.0, Vector3.ZERO, 0.0, false, 0.0)
	assert_float(coarse.angle_z).is_equal_approx(fine.angle_z, 0.5)
