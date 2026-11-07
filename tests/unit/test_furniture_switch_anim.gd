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


func test_the_fans_blade_picture_steps_with_its_speed_and_holds_when_stopped() -> void:
	var node := auto_free(load("res://features/house/furniture.tscn").instantiate()) as Node3D
	node.set("data", null)
	node.set("visual_id", &"int_nog_fan")
	add_child(node)
	var fx: FurnitureSwitchAnim = node.get_node("FurnitureSwitchAnim") as FurnitureSwitchAnim
	assert_int(fx._blades.size()).is_equal(1)
	var first: Texture2D = fx._blades[0].albedo_texture
	for _i: int in 12:
		fx._speed = FurnitureSwitchAnim.FULL_SPEED
		fx._blur_tick()
	assert_object(fx._blades[0].albedo_texture).is_not_same(first)
	var held: Texture2D = fx._blades[0].albedo_texture
	for _i: int in 30:
		fx._speed = 0.0
		fx._blur_tick()
	assert_object(fx._blades[0].albedo_texture).is_same(held)


func test_the_slot_machine_sounds_only_while_the_reels_turn() -> void:
	var data := FurnitureData.new()
	data.visual_id = &"int_sum_slot"
	var entry := FurniturePlacement.new()
	assert_int(FurnitureAmbience.level_for(data, entry)).is_equal(-1)
	entry.spinning = true
	assert_int(FurnitureAmbience.level_for(data, entry)).is_equal(2)
