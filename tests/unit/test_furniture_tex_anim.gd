class_name TestFurnitureTexAnim
extends GdUnitTestSuite

## Screens and reels bind their own pictures (`gSPSegment(…, G_MWO_SEGMENT_8, tex)`).


func _piece(visual: StringName) -> Node3D:
	var node := auto_free(load("res://features/house/furniture.tscn").instantiate()) as Node3D
	node.set("data", null)
	node.set("visual_id", visual)
	add_child(node)
	return node


func test_the_televisions_have_their_frames_from_the_decomp() -> void:
	var tv: Dictionary = FurnitureTexAnim.spec_for(&"int_sum_tv01")
	assert_int((tv["on"] as Array).size()).is_equal(27)
	assert_str(String(tv["off"])).is_equal("int_sum_tv01_front1_TA_tex_txt")
	assert_int((FurnitureTexAnim.spec_for(&"int_sum_tv02")["on"] as Array).size()).is_equal(5)
	assert_int((FurnitureTexAnim.spec_for(&"int_sum_fruittv01")["on"] as Array).size()).is_equal(13)
	assert_int((FurnitureTexAnim.spec_for(&"int_kon_snowtv")["on"] as Array).size()).is_equal(30)
	var slot: Dictionary = FurnitureTexAnim.spec_for(&"int_sum_slot")
	assert_int((slot["on"] as Array).size()).is_equal(121)
	assert_int(int(slot["wrap_frames"])).is_equal(242)


func test_a_television_shows_its_off_picture_then_steps_when_on() -> void:
	var node: Node3D = _piece(&"int_sum_tv01")
	var fx: FurnitureTexAnim = node.get_node_or_null("FurnitureTexAnim") as FurnitureTexAnim
	assert_object(fx).is_not_null()
	## No room: counted as on, so it is already running; stepping two ticks per frame.
	var frames: Array = fx._spec["on"] as Array
	fx._counter = 0
	assert_str(fx._current()).is_equal(String(frames[0]))
	fx._counter = 6
	assert_str(fx._current()).is_equal(String(frames[3]))


func test_a_piece_with_no_swap_gets_no_component() -> void:
	assert_object(_piece(&"int_sum_chair01").get_node_or_null("FurnitureTexAnim")).is_null()


func test_the_slot_reels_run_only_while_spinning() -> void:
	var node: Node3D = _piece(&"int_sum_slot")
	var fx: FurnitureTexAnim = node.get_node_or_null("FurnitureTexAnim") as FurnitureTexAnim
	assert_object(fx).is_not_null()
	assert_bool(fx._running()).is_false()
	var spin: FurnitureSwitchAnim = node.get_node("FurnitureSwitchAnim") as FurnitureSwitchAnim
	spin.switched()
	assert_bool(fx._running()).is_true()
