class_name TestLighthouse
extends GdUnitTestSuite

## `LighthouseSwitch` / `LighthouseBeacon` on/off logic (`aLS_AutoSwitch`, night-window
## simplification of `aLS_NiceSwitchOnTime`) — not the "lighthouse period" quest/boat-travel
## system, which is out of scope (`docs/scope.md`).


func before_test() -> void:
	Clock.paused = true


func after_test() -> void:
	Clock.paused = false


func _lighthouse() -> Node3D:
	var node: Node3D = auto_free(load("res://scenes/world/buildings/lighthouse.tscn").instantiate()) as Node3D
	add_child(node)
	return node


func test_switch_defaults_on_at_night_off_by_day() -> void:
	var node: Node3D = _lighthouse()
	var switch: Node = node.get_node("LighthouseSwitch")
	var beacon: Node = node.get_node("Beacon")
	Clock.hour = 20
	switch.recheck()
	assert_bool(switch.is_on()).is_true()
	assert_bool(bool(beacon.get("on"))).is_true()
	Clock.hour = 12
	switch.recheck()
	assert_bool(switch.is_on()).is_false()
	assert_bool(bool(beacon.get("on"))).is_false()


func test_interact_toggles_and_overrides_auto_until_next_boundary() -> void:
	var node: Node3D = _lighthouse()
	var switch: Node = node.get_node("LighthouseSwitch")
	var beacon: Node = node.get_node("Beacon")
	Clock.hour = 12
	switch.recheck()
	assert_bool(switch.is_on()).is_false()
	switch.interact(Interaction.of(Interaction.TOGGLE, "Turn on the light"), null)
	assert_bool(switch.is_on()).is_true()
	assert_bool(bool(beacon.get("on"))).is_true()
	## Manual override persists through hours that aren't a window boundary.
	Clock.hour = 13
	assert_bool(switch.is_on()).is_true()
	## The next boundary (18:00 or 05:00) resets the override back to auto.
	switch._on_hour_changed(18)
	assert_bool(switch.is_on()).is_false()
	assert_bool(bool(beacon.get("on"))).is_false()


func test_beacon_drives_the_real_decomp_sweep_animation() -> void:
	## `obj_s_toudai`'s converted GLB carries the real sweep (`AnimationPlayer` rotating the
	## `obj_s_toudai_arm_model` bone). `GeneratedVisual.attach` stops autoplay on every
	## import, so nothing plays it unless the beacon explicitly does — verify it actually
	## does, not just that the on/off booleans flip.
	var node: Node3D = _lighthouse()
	var beacon: Node = node.get_node("Beacon")
	await get_tree().process_frame ## let the deferred AnimationPlayer lookup resolve.
	## The tower's own AnimationPlayer, not the switch prop's separate one — same scope the
	## beacon script itself searches (`node/GeneratedVisual/...`).
	var anim: AnimationPlayer = node.get_node("GeneratedVisual").find_child(
		"AnimationPlayer", true, false
	) as AnimationPlayer
	assert_object(anim).is_not_null()
	assert_bool(anim.has_animation(&"obj_s_toudai")).is_true()

	beacon.set("on", false)
	assert_bool(anim.is_playing()).is_false()
	assert_float(anim.current_animation_position).is_equal_approx(0.0, 0.001)

	beacon.set("on", true)
	assert_bool(anim.is_playing()).is_true()
	assert_str(anim.current_animation).is_equal("obj_s_toudai")
	assert_that(anim.get_animation(&"obj_s_toudai").loop_mode).is_equal(Animation.LOOP_LINEAR)

	beacon.set("on", false)
	assert_bool(anim.is_playing()).is_false()
	assert_float(anim.current_animation_position).is_equal_approx(0.0, 0.001)


func test_beacon_head_spins_only_when_on() -> void:
	var beacon: Node3D = auto_free(
		load("res://scenes/world/buildings/lighthouse_beacon.tscn").instantiate()
	) as Node3D
	add_child(beacon)
	var head: Node3D = beacon.get_node("Head") as Node3D
	beacon.set("on", false)
	beacon._process(1.0)
	assert_float(head.rotation.y).is_equal_approx(0.0, 0.0001)
	beacon.set("on", true)
	beacon._process(1.0)
	assert_float(head.rotation.y).is_greater(0.0)
