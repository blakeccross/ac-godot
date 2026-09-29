class_name TestWindowSunshine
extends GdUnitTestSuite

## `ROOM_SUNSHINE` beams per scene actor table, and the light-switch window light.


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true
	Game.reset_session()
	InteriorCatalog.reset()


func _room(kind: Room.Kind, id: StringName) -> Room:
	var room := Room.new()
	room.kind = kind
	room.id = id
	return room


func test_player_floors_follow_the_house_size() -> void:
	var main: Room = _room(Room.Kind.PLAYER, PlayerHouse.MAIN)
	var house := House.new()
	var want: Array = [
		[Vector3(40, 0, 120), Vector3(200, 0, 120)],  ## player_room_s
		[Vector3(40, 0, 160), Vector3(280, 0, 160)],  ## player_room_m
		[Vector3(40, 0, 200), Vector3(360, 0, 200)],  ## player_room_l
		[Vector3(40, 0, 200), Vector3(360, 0, 200)],  ## player_room_ll1
	]
	for tier: int in want.size():
		house.size_tier = tier as House.SizeTier
		assert_array(WindowSunshine.actors_for(main, house)).is_equal(want[tier])
	## player_room_ll2; the basement scenes have no beams.
	assert_array(WindowSunshine.actors_for(_room(Room.Kind.PLAYER, PlayerHouse.UPPER), house)) \
		.is_equal([Vector3(40, 0, 160), Vector3(280, 0, 160)])
	assert_array(WindowSunshine.actors_for(_room(Room.Kind.PLAYER, PlayerHouse.BASEMENT), house)) \
		.is_empty()


func test_villager_homes_use_npc_room01() -> void:
	var room: Room = _room(Room.Kind.NPC, &"npc_test")
	assert_array(WindowSunshine.actors_for(room)).is_equal([Vector3(40, 0, 160), Vector3(282, 0, 160)])
	assert_bool(WindowSunshine.has_light_switch(room)).is_true()
	assert_bool(WindowSunshine.has_light_switch(_room(Room.Kind.NEEDLEWORK, &"needlework"))).is_false()


func test_light_switch_keeps_the_window_light_partly_open() -> void:
	## Lights off by day: `(1 − 0.14) · 0.78 + 0.22`; lights on at night: 0.22.
	assert_float(WindowSunshine.window_light_target(9 * 3600, true)).is_equal_approx(0.8908, 0.0001)
	assert_float(WindowSunshine.window_light_target(22 * 3600, true)).is_equal_approx(0.22, 0.0001)
	## Without a switch the window closes at night.
	assert_float(WindowSunshine.window_light_target(22 * 3600, false)).is_equal(0.0)
	## Both close around noon's `s16` mark.
	assert_float(WindowSunshine.window_light_target(12 * 3600 + 30, true)).is_equal(0.0)


func test_build_adds_beams_to_a_villager_home() -> void:
	var session := IndoorSession.new()
	var room: Room = InteriorCatalog.room_template(InteriorCatalog.npc_room_id(&"test_villager"))
	if room == null:
		room = _room(Room.Kind.NPC, &"npc_test_villager")
	session.bind(room)
	var root := Node3D.new()
	auto_free(root)
	add_child(root)
	InteriorBuilder.build(root, session)
	var left: Node3D = root.get_node_or_null("Terrain/SunshineL") as Node3D
	var right: Node3D = root.get_node_or_null("Terrain/SunshineR") as Node3D
	assert_object(left).is_not_null()
	assert_object(right).is_not_null()
	assert_bool(right.get("light_switch")).is_true()
	assert_float(right.position.x).is_greater(left.position.x)


func test_post_office_beams_stand_on_the_floor() -> void:
	## `ef_room_sunshine_posthouse`: police anchor X, but no −40 Y.
	assert_vector(PostDisplay.sunshine_anchor_gx(PostDisplay.SUNSHINE_L_GX, true)) \
		.is_equal(Vector3(38.0, 1.0, 160.0))
	assert_vector(PostDisplay.sunshine_anchor_gx(PostDisplay.SUNSHINE_R_GX, false)) \
		.is_equal(Vector3(280.0, 1.0, 160.0))


func test_museum_beams_use_the_police_anchor() -> void:
	## `ef_room_sunshine_museum` args 2 / 3: X −2 / +0 and `1 + BgY − 40`.
	assert_vector(MuseumDisplay.sunshine_anchor_gx(MuseumDisplay.ENTRANCE_SUNSHINE_GX[0], true, false)) \
		.is_equal(Vector3(121.0, -39.0, 180.0))
	assert_vector(MuseumDisplay.sunshine_anchor_gx(MuseumDisplay.ENTRANCE_SUNSHINE_GX[3], false, false)) \
		.is_equal(Vector3(360.0, -39.0, 380.0))
	## `ef_room_sunshine_minsect` puts Y back on the actor's own 0 each frame.
	assert_vector(MuseumDisplay.sunshine_anchor_gx(MuseumDisplay.INSECT_SUNSHINE_GX[1], false, true)) \
		.is_equal(Vector3(520.0, -40.0, 280.0))
