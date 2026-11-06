class_name TestFurnitureSwitchAnim
extends GdUnitTestSuite

## Fan, toy train and slot machine clips follow their switch.


func test_the_ease_coasts_toward_its_target_and_snaps() -> void:
	var v: float = 0.0
	for _i: int in 400:
		v = FurnitureSwitchAnim.ease_step(v, FurnitureSwitchAnim.FULL_SPEED, 0.0253)
	assert_float(v).is_equal(FurnitureSwitchAnim.FULL_SPEED)
	var first: float = FurnitureSwitchAnim.ease_step(0.0, 0.5, 0.0253)
	assert_float(first).is_equal_approx(0.5 * 0.0253, 0.0001)
	for _i: int in 600:
		v = FurnitureSwitchAnim.ease_step(v, 0.0, 0.0513)
	assert_float(v).is_equal(0.0)


func test_the_fan_and_the_train_follow_the_switch_but_a_lamp_does_not() -> void:
	assert_bool(FurnitureSwitchAnim.wants(&"int_nog_fan")).is_true()
	assert_bool(FurnitureSwitchAnim.wants(&"int_sum_kisha")).is_true()
	assert_bool(FurnitureSwitchAnim.wants(&"int_sum_slot")).is_true()
	assert_bool(FurnitureSwitchAnim.wants(&"int_sum_chair01")).is_false()


func test_a_fan_on_a_real_model_starts_at_the_speed_of_its_switch() -> void:
	var node := auto_free(load("res://features/house/furniture.tscn").instantiate()) as Node3D
	node.set("data", null)
	node.set("visual_id", &"int_nog_fan")
	add_child(node)
	var fx: FurnitureSwitchAnim = node.get_node_or_null("FurnitureSwitchAnim") as FurnitureSwitchAnim
	assert_object(fx).is_not_null()
	var anim: AnimationPlayer = VisualAnimation.find_animation_player(node)
	assert_float(anim.speed_scale).is_equal_approx(1.0, 0.001)  ## no room: counted as on
