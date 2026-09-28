class_name TestLighthouse
extends GdUnitTestSuite

## Lighthouse (`ac_toudai`, `ac_lighthouse_switch`, `mSC_LightHouse_*`): the quest state,
## the tower lamp's schedule and sweep, the north door, and the switch room.

const LAMP_SCENE := "res://scenes/world/buildings/lighthouse_beacon.tscn"
const TOWER_SCENE := "res://scenes/world/buildings/lighthouse.tscn"
const SWITCH_SCENE := "res://scenes/world/interiors/lighthouse_switch.tscn"

var _saved_book: Dictionary = {}
var _saved_clock: Dictionary = {}


func before_test() -> void:
	Clock.paused = true
	_saved_clock = Clock.to_dict()
	_saved_book = Game.lighthouse.to_save()
	Game.lighthouse.clear()


func after_test() -> void:
	Game.lighthouse.apply_snapshot(_saved_book)
	Clock.apply_snapshot(_saved_clock)
	Clock.paused = false


## --- LighthouseBook -------------------------------------------------------------------


func test_no_quest_lamp_runs_18_to_05_and_door_stays_shut() -> void:
	var book := LighthouseBook.new()
	assert_bool(book.lamp_on(2001, 7, 15, 17)).is_false()
	assert_bool(book.lamp_on(2001, 7, 15, 18)).is_true()
	assert_bool(book.lamp_on(2001, 7, 16, 4)).is_true()
	assert_bool(book.lamp_on(2001, 7, 16, 5)).is_false()
	for hour: int in 24:
		assert_bool(book.door_open(2001, 7, 15, hour)).is_false()
	assert_int(book.switch_mode(2001, 7, 15, 12)).is_equal(LighthouseBook.SwitchMode.OFF)
	assert_int(book.switch_mode(2001, 7, 15, 20)).is_equal(LighthouseBook.SwitchMode.AUTO_ON)


func test_quest_periods_follow_the_day_it_was_given() -> void:
	var book := LighthouseBook.new()
	book.start_quest(2002, 1, 15)
	var d := func(day: int) -> int: return EventDates.ordinal(2002, 1, day)
	assert_int(book.period_on(d.call(14))).is_equal(LighthouseBook.Period.NONE)
	assert_int(book.period_on(d.call(15))).is_equal(LighthouseBook.Period.GIVEN)
	assert_int(book.period_on(d.call(16))).is_equal(LighthouseBook.Period.NIGHTS)
	assert_int(book.period_on(d.call(22))).is_equal(LighthouseBook.Period.NIGHTS)
	assert_int(book.period_on(d.call(23))).is_equal(LighthouseBook.Period.REWARD)
	assert_int(book.period_on(EventDates.ordinal(2002, 2, 1))).is_equal(LighthouseBook.Period.REWARD)
	assert_int(book.period_on(EventDates.ordinal(2002, 2, 2))).is_equal(LighthouseBook.Period.NONE)
	assert_int(book.night_index(d.call(16))).is_equal(0)
	assert_int(book.night_index(d.call(22))).is_equal(6)


func test_quest_night_lamp_waits_for_the_switch() -> void:
	var book := LighthouseBook.new()
	book.start_quest(2002, 1, 15)
	## The day it is given the lamp still runs itself.
	assert_bool(book.lamp_on(2002, 1, 15, 20)).is_true()
	## First quest night: dark until the switch, the door open 18:00–21:59 only.
	assert_bool(book.lamp_on(2002, 1, 16, 20)).is_false()
	assert_bool(book.door_open(2002, 1, 16, 17)).is_false()
	assert_bool(book.door_open(2002, 1, 16, 18)).is_true()
	assert_bool(book.door_open(2002, 1, 16, 21)).is_true()
	assert_bool(book.door_open(2002, 1, 16, 22)).is_false()
	assert_bool(book.door_open(2002, 1, 16, 20, true)).is_false()
	assert_int(book.switch_mode(2002, 1, 16, 20)).is_equal(LighthouseBook.SwitchMode.MANUAL)
	book.switch_on(2002, 1, 16)
	assert_bool(book.lamp_on(2002, 1, 16, 21)).is_true()
	assert_bool(book.door_open(2002, 1, 16, 21)).is_false()
	## Still that night's switch after midnight (6 h rollover), not the next night's.
	assert_bool(book.lamp_on(2002, 1, 17, 3)).is_true()
	assert_bool(book.lamp_on(2002, 1, 17, 19)).is_false()
	assert_bool(book.contributed).is_true()


func test_book_save_round_trip() -> void:
	var book := LighthouseBook.new()
	book.start_quest(2002, 2, 12)
	book.switch_on(2002, 2, 14)
	var copy := LighthouseBook.new()
	copy.apply_snapshot(book.to_save())
	assert_int(copy.start_ordinal).is_equal(book.start_ordinal)
	assert_int(copy.nights_lit).is_equal(book.nights_lit)
	assert_bool(copy.quest_taken).is_true()
	assert_bool(copy.contributed).is_true()


## --- Tower lamp -----------------------------------------------------------------------


func _lamp() -> Node:
	var lamp: Node = auto_free(load(LAMP_SCENE).instantiate())
	lamp.set("follow_clock", false)
	add_child(lamp)
	return lamp


func test_lamp_rests_on_frame_51_with_no_beam() -> void:
	var lamp: Node = _lamp()
	for _i: int in 30:
		lamp.tick()
	assert_bool(lamp.is_sweeping()).is_false()
	assert_float(lamp.get("frame")).is_equal(51.0)
	assert_float(lamp.beam_color().a).is_equal(0.0)


func test_lamp_sweeps_at_half_speed_and_peaks_on_frame_51() -> void:
	var lamp: Node = _lamp()
	lamp.set("lit", true)
	lamp.tick()
	assert_bool(lamp.is_sweeping()).is_true()
	## One full turn: 99 frames at 0.5 a tick.
	for _i: int in 198:
		lamp.tick()
	assert_float(lamp.get("frame")).is_equal_approx(51.0, 0.01)
	assert_float(lamp.get("beam_alpha")).is_equal(240.0)
	assert_float(lamp.get("beam_blue")).is_equal(220.0)
	assert_float(lamp.beam_color().a).is_greater(0.0)
	## Half a turn later the beam faces away and has faded out.
	for _i: int in 99:
		lamp.tick()
	assert_float(lamp.get("beam_alpha")).is_less(1.0)


func test_lamp_finishes_its_turn_before_stopping() -> void:
	var lamp: Node = _lamp()
	lamp.set("lit", true)
	for _i: int in 40:
		lamp.tick()
	lamp.set("lit", false)
	lamp.tick()
	assert_bool(lamp.is_sweeping()).is_true()
	for _i: int in 400:
		lamp.tick()
		if not lamp.is_sweeping():
			break
	assert_bool(lamp.is_sweeping()).is_false()
	assert_float(lamp.get("frame")).is_equal(51.0)


func test_lamp_follows_the_book() -> void:
	var lamp: Node = auto_free(load(LAMP_SCENE).instantiate())
	add_child(lamp)
	Clock.set_datetime(2001, 7, 15, 12)
	lamp.tick()
	assert_bool(lamp.get("lit")).is_false()
	Clock.set_datetime(2001, 7, 15, 20)
	lamp.tick()
	assert_bool(lamp.get("lit")).is_true()
	Game.lighthouse.start_quest(2001, 7, 14)
	lamp.tick()
	assert_bool(lamp.get("lit")).is_false()


## --- Tower ----------------------------------------------------------------------------


func test_tower_has_no_field_switch_and_a_north_door() -> void:
	var tower: Node3D = auto_free(load(TOWER_SCENE).instantiate()) as Node3D
	add_child(tower)
	assert_object(tower.get_node_or_null("LighthouseSwitch")).is_null()
	var door: Node3D = tower.get_node("Door") as Node3D
	assert_float(door.position.z).is_less(0.0)
	assert_float(door.position.x).is_equal_approx(0.0, 0.01)
	var stand: Vector3 = StructureDoor.exit_stand(tower)
	assert_float(stand.z - tower.global_position.z).is_equal_approx(-70.0 * FieldCatalog.GX_TO_METERS, 0.01)


func test_door_only_opens_on_an_unswitched_quest_night() -> void:
	var room: Room = InteriorCatalog.room_template(&"lighthouse")
	Clock.set_datetime(2002, 1, 16, 20)
	assert_bool(InteriorCatalog.is_open_now(room)).is_false()
	Game.lighthouse.start_quest(2002, 1, 15)
	assert_bool(InteriorCatalog.is_open_now(room)).is_true()
	Game.lighthouse.switch_on_now()
	assert_bool(InteriorCatalog.is_open_now(room)).is_false()


func test_structure_offset_raises_the_2x2_tower() -> void:
	var data := WorldData.new()
	data.columns = 32
	data.rows = 32
	var b := BuildingPlacement.new()
	b.id = &"lighthouse"
	b.visual_id = &"obj_s_toudai"
	b.cell = Vector2i(10, 10)
	b.footprint = Vector2i(2, 2)
	data.buildings.append(b)
	StructureOffset.apply(data)
	for cell: Vector2i in [Vector2i(10, 10), Vector2i(11, 10), Vector2i(10, 11), Vector2i(11, 11)]:
		assert_bool(FieldCollision.is_raised_plus(cell)).is_true()
	## The door stand north of the tower stays walkable.
	assert_bool(FieldCollision.is_raised_plus(Vector2i(10, 9))).is_false()
	FieldCollision.clear_plus()


## --- Switch room ----------------------------------------------------------------------


func test_room_template_matches_rom_toudai() -> void:
	var room: Room = InteriorCatalog.room_template(&"lighthouse")
	assert_that(room.door_cell).is_equal(Vector2i(2, 0))
	assert_that(room.inner_origin).is_equal(Vector2i(1, 1))
	assert_that(room.inner_size).is_equal(Vector2i(4, 5))
	assert_str(InteriorCatalog.scene_path(&"lighthouse")).ends_with("interiors/lighthouse.tscn")
	var gaps: Array[Dictionary] = InteriorShellBuilder.shell_door_gaps(room, WorldGrid.new())
	assert_int(gaps.size()).is_equal(1)
	assert_str(String(gaps[0]["side"])).is_equal("north")
	Game.prepare_interior_spawn(&"lighthouse")
	assert_that(Game.interior_spawn_gx).is_equal(LighthouseRoom.SPAWN_GX)
	assert_float(Game.interior_spawn_yaw).is_equal_approx(
		WorldGrid.yaw_for_facing(WorldGrid.Facing.SOUTH), 0.001
	)


func _switch() -> Node3D:
	var node: Node3D = auto_free(load(SWITCH_SCENE).instantiate()) as Node3D
	node.set("follow_clock", false)
	add_child(node)
	return node


func test_switch_room_runs_itself_outside_the_quest() -> void:
	var sw: Node3D = _switch()
	sw.enter(LighthouseBook.SwitchMode.OFF)
	assert_bool(sw.get("lever_on")).is_false()
	## Night: the lever flips, then the drive spins up and the light eases on.
	for _i: int in 200:
		sw.tick(LighthouseBook.SwitchMode.AUTO_ON)
	assert_bool(sw.get("lever_on")).is_true()
	assert_int(sw.get("pole_state")).is_equal(1)
	assert_float(sw.get("pole_speed")).is_greater(0.0)
	assert_float(sw.get("light")).is_greater(0.5)
	## Morning: the drive winds down, the light goes out, then the lever drops.
	for _i: int in 2000:
		sw.tick(LighthouseBook.SwitchMode.OFF)
	assert_bool(sw.get("lever_on")).is_false()
	assert_float(sw.get("pole_speed")).is_equal_approx(0.0, 0.001)
	assert_float(sw.get("light")).is_equal(0.0)


func test_switch_room_enters_running_at_night() -> void:
	var sw: Node3D = _switch()
	sw.enter(LighthouseBook.SwitchMode.AUTO_ON)
	assert_bool(sw.get("lever_on")).is_true()
	assert_float(sw.get("pole_speed")).is_equal(0.5)
	assert_float(sw.get("light")).is_equal(1.0)
	assert_array(sw.get_interactions(null)).is_empty()


func test_quest_night_switch_lights_tonight() -> void:
	Game.lighthouse.start_quest(2002, 1, 15)
	Clock.set_datetime(2002, 1, 16, 19)
	var node: Node3D = auto_free(load(SWITCH_SCENE).instantiate()) as Node3D
	add_child(node)
	assert_bool(node.get("lever_on")).is_false()
	assert_bool(Game.lighthouse.lamp_on_now()).is_false()
	var actions: Array[Interaction] = node.get_interactions(null)
	assert_int(actions.size()).is_equal(1)
	assert_str(String(actions[0].player_anim)).is_equal("ply_1_light_on1")
	assert_bool(node.interact(actions[0], null)).is_true()
	assert_bool(node.get("lever_on")).is_true()
	assert_bool(Game.lighthouse.lamp_on_now()).is_true()
	assert_bool(Game.lighthouse.door_open_now()).is_false()
	assert_array(node.get_interactions(null)).is_empty()
