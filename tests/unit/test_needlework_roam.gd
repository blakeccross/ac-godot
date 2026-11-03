class_name TestNeedleworkRoam
extends GdUnitTestSuite

## Mabel's area / waypoint tables and `aNNW_MY_PROC_*` machine (`_schedule.c_inc`).


func test_area_lookup_matches_table() -> void:
	## ux/uz = GX / 40. Entrance mat cells (4-5, 7-8) are area 6; the west counter is 0.
	assert_int(NeedleworkRoam.area_at(Vector2(180, 300))).is_equal(6)
	assert_int(NeedleworkRoam.area_at(Vector2(60, 180))).is_equal(0)
	assert_int(NeedleworkRoam.area_at(Vector2(200, 60))).is_equal(7)
	assert_int(NeedleworkRoam.area_at(Vector2(340, 140))).is_equal(5)
	assert_int(NeedleworkRoam.area_at(Vector2(10, 10))).is_equal(NeedleworkRoam.AREA_NONE)
	assert_int(NeedleworkRoam.area_at(Vector2(-5, 100))).is_equal(NeedleworkRoam.AREA_NONE)


func test_next_target_stays_when_player_close_in_near_area() -> void:
	var roam := NeedleworkRoam.new()
	## Both in the displays' middle row: same area, inside 115 GX → stay.
	assert_int(roam.next_target(Vector2(200, 220), Vector2(240, 220), 40.0, false)).is_equal(NeedleworkRoam.STAY)
	## Same area but far → go to the player.
	assert_int(roam.next_target(Vector2(180, 220), Vector2(300, 220), 120.0, false)).is_equal(NeedleworkRoam.TO_PLAYER)
	## Different, non-adjacent areas → roam.
	assert_int(roam.next_target(Vector2(60, 180), Vector2(300, 220), 260.0, false)).is_equal(NeedleworkRoam.ROAM)
	## Trade wait tightens the stay range to 55 GX.
	assert_int(roam.next_target(Vector2(200, 220), Vector2(300, 220), 100.0, true)).is_equal(NeedleworkRoam.TO_PLAYER)


func test_waypoints_walk_toward_the_players_area() -> void:
	var roam := NeedleworkRoam.new()
	## From the entrance area (4) with the player on the east side → waypoint 9.
	roam.target = 0
	assert_int(roam.next_waypoint(Vector2(340, 140), Vector2(180, 220))).is_equal(9)
	## From the west counter (0) she alternates between 2 and 3.
	roam.target = 0
	assert_int(roam.next_waypoint(Vector2(300, 100), Vector2(60, 180))).is_equal(2)
	roam.target = 2
	assert_int(roam.next_waypoint(Vector2(300, 100), Vector2(60, 180))).is_equal(3)


func test_unmapped_ring_keeps_last_area() -> void:
	var roam := NeedleworkRoam.new()
	roam.track(Vector2(200, 60), Vector2(180, 220))
	assert_int(roam.player_area).is_equal(7)
	roam.track(Vector2(10, 10), Vector2(180, 220))
	assert_int(roam.player_area).is_equal(7)


func test_brain_runs_to_a_far_player_then_stops_close() -> void:
	var roam := NeedleworkRoam.new()
	roam.reset(0.0)
	var me: Vector3 = NeedleworkRoam.to_world(Vector2(180, 220))
	var player: Vector3 = NeedleworkRoam.to_world(Vector2(300, 220))  ## same area, 120 GX away
	var yaw := 0.0
	for _i in 600:
		roam.tick(1.0 / 60.0, me, player, yaw)
		yaw = roam.yaw
		me += roam.velocity / 60.0
	var gap: float = NeedleworkRoam.to_gx(me).distance_to(NeedleworkRoam.to_gx(player))
	assert_float(gap).is_less(115.0)
	assert_bool(roam.is_waiting()).is_true()


func test_trade_walk_ends_waiting_close_to_the_player() -> void:
	var roam := NeedleworkRoam.new()
	roam.reset(0.0)
	roam.waiting_on_trade = true
	var me: Vector3 = NeedleworkRoam.to_world(Vector2(210, 250))
	var player: Vector3 = NeedleworkRoam.to_world(Vector2(260, 140))
	var yaw := 0.0
	for _i in 1200:
		roam.tick(1.0 / 60.0, me, player, yaw)
		yaw = roam.yaw
		me += roam.velocity / 60.0
		if roam.is_waiting() and _i > 5:
			break
	var gap: float = NeedleworkRoam.to_gx(me).distance_to(NeedleworkRoam.to_gx(player))
	assert_float(gap).is_less(60.0)


func test_trend_report_reads_the_rom_text_with_position_strings() -> void:
	var cloth: Array = NeedleworkTalk.trend_items("green mesh", 0, false)
	assert_str(str(cloth[0])).is_equal("green mesh")
	assert_str((cloth[1] as PackedStringArray)[1]).is_equal("far left")
	var umb: Array = NeedleworkTalk.trend_items("ducky umbrella", 7, true)
	assert_str((umb[1] as PackedStringArray)[0]).is_equal("ducky umbrella")
	assert_str((umb[1] as PackedStringArray)[2]).is_equal("far right")
	var pages: Array[String] = NeedleworkTalk.trend_pages("x", 6, false)
	assert_bool(pages.size() > 0).is_true()
	assert_str(" ".join(pages)).contains("{item0}")
