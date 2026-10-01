extends GdUnitTestSuite

## Groundhog Day's pop-up (`ac_ev_majin`, `aEMJ_set_force_talk_info`).

const GroundhogResetti := preload("res://scenes/world/events/groundhog_resetti.gd")


func test_the_line_follows_the_weather() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	for _i: int in 20:
		assert_int(GroundhogResetti.speech_msg(&"clear", rng)).is_between(0x3DAF, 0x3DB1)
		assert_int(GroundhogResetti.speech_msg(&"snow", rng)).is_between(0x3DB2, 0x3DB4)
	assert_int(GroundhogResetti.speech_msg(&"rain", rng)).is_equal(0x3DAF)
