class_name TestWindowLights
extends GdUnitTestSuite

## Per-building `*_ctrl_light` rules for facade window panes and ground spill.


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true
	Game.reset_session()
	InteriorCatalog.reset()


func _host(visual_id: StringName, occupant_id: StringName) -> Node:
	var script := GDScript.new()
	script.source_code = "extends Node\nvar visual_id: StringName = &\"\"\nvar occupant_id: StringName = &\"\"\n"
	script.reload()
	var node: Node = auto_free(Node.new())
	node.set_script(script)
	node.set("visual_id", visual_id)
	node.set("occupant_id", occupant_id)
	return node


func test_plain_nodes_keep_the_callers_state() -> void:
	assert_that(VisualWindowLight.host_lights_on(auto_free(Node.new()))).is_null()


func test_police_box_lights_every_night_the_museum_until_six() -> void:
	var police := _host(&"obj_s_kouban", &"")
	var museum := _host(&"obj_s_museum", &"")
	Clock.set_datetime(2001, 6, 5, 5)
	assert_bool(bool(VisualWindowLight.host_lights_on(police))).is_false()
	assert_bool(bool(VisualWindowLight.host_lights_on(museum))).is_true()
	Clock.set_datetime(2001, 6, 5, 23)
	assert_bool(bool(VisualWindowLight.host_lights_on(police))).is_true()


func test_the_cranny_goes_dark_once_it_closes() -> void:
	var shop := _host(&"obj_s_shop1", &"acre_shop")
	Clock.set_datetime(2001, 6, 5, 20)
	assert_bool(Game.shops.nook_is_open()).is_true()
	assert_bool(bool(VisualWindowLight.host_lights_on(shop))).is_true()
	Clock.set_datetime(2001, 6, 5, Game.shops.nook_close_hour())
	assert_bool(bool(VisualWindowLight.host_lights_on(shop))).is_false()
	Clock.set_datetime(2001, 6, 5, 12)
	assert_bool(bool(VisualWindowLight.host_lights_on(shop))).is_false()


## `aNW_check_opend`: open 7:00 to 2:00, so it's dark from 2 until dawn.
func test_able_sisters_is_dark_after_hours() -> void:
	var able := _host(&"obj_s_needlework", &"able_sisters")
	Clock.set_datetime(2001, 6, 5, 23)
	assert_bool(bool(VisualWindowLight.host_lights_on(able))).is_true()
	Clock.set_datetime(2001, 6, 5, 3)
	assert_bool(bool(VisualWindowLight.host_lights_on(able))).is_false()
	Clock.set_datetime(2001, 6, 5, 1)
	assert_bool(bool(VisualWindowLight.host_lights_on(able))).is_true()
