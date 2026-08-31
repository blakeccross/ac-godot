class_name TestResources
extends GdUnitTestSuite


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true


func after_test() -> void:
	Clock.reset_to_default()
	Clock.paused = false


func test_item_catalog() -> void:
	var apple: ItemData = load("res://data/items/apple.tres")
	assert_that(apple).is_not_null()
	assert_that(apple.id).is_equal(&"apple")
	assert_int(apple.max_stack).is_equal(9)
	assert_that(apple.category).is_equal(ItemData.Category.FRUIT)


func test_furniture_extends_item() -> void:
	var chair: FurnitureData = load("res://data/furniture/wood_chair.tres")
	assert_that(chair).is_not_null()
	assert_that(chair.indoor).is_true()
	assert_that(chair.footprint).is_equal(Vector2i(1, 1))
	assert_bool(chair.can_sit).is_true()
	assert_that(chair.kind).is_equal(FurnitureData.Kind.CHAIR)
	assert_that(chair.contact).is_equal(FurnitureData.Contact.CHAIR_FRONT)
	var table: FurnitureData = load("res://data/furniture/wood_table.tres")
	assert_that(table.footprint).is_equal(Vector2i(2, 1))
	assert_bool(table.can_sit).is_false()
	assert_bool(table.blocks_walk).is_true()
	assert_that(table.placement).is_equal(FurnitureData.Placement.TABLE)


func test_boy_looks_schedule() -> void:
	var schedule: ScheduleData = load("res://data/schedules/pip_weekday.tres")
	assert_that(schedule.activity_at(7)).is_equal(&"sleep")
	assert_that(schedule.activity_at(8)).is_equal(&"in_house")
	assert_that(schedule.activity_at(9)).is_equal(&"field")
	assert_that(schedule.activity_at(12)).is_equal(&"in_house")
	assert_that(schedule.activity_at(14)).is_equal(&"field")
	assert_that(schedule.activity_at(20)).is_equal(&"in_house")
	assert_that(schedule.activity_at(22)).is_equal(&"sleep")
	Clock.apply_snapshot({ "year": 2001, "month": 1, "day": 1, "hour": 10, "minute": 0 })
	assert_that(schedule.activity_now()).is_equal(&"field")


func test_acre_grid_defaults() -> void:
	var acre: AcreData = load("res://data/acres/plot_a.tres")
	assert_int(acre.columns).is_equal(16)
	assert_int(acre.rows).is_equal(16)
	assert_int(acre.water_cells.size()).is_equal(4)


func test_villager_points_at_schedule() -> void:
	var filbert: VillagerData = load("res://data/villagers/filbert.tres")
	assert_that(filbert.display_name).is_equal("Filbert")
	assert_that(filbert.personality).is_not_null()
	assert_that(filbert.schedule_table()).is_not_null()
	assert_that(filbert.schedule_table().activity_at(9)).is_equal(&"field")


## Dace holds NIGHT, MORNING and EVENING but not DAY, so it is out from 9am to 4pm.
func test_dace_uses_time_slots() -> void:
	var dace: FishData = load("res://data/creatures/dace.tres")
	assert_bool(dace.is_available(1, 16)).is_true()
	assert_bool(dace.is_available(1, 8)).is_true()
	assert_bool(dace.is_available(1, 9)).is_false()
	assert_bool(dace.is_available(1, 15)).is_false()
	Clock.apply_snapshot({ "year": 2001, "month": 1, "day": 1, "hour": 17, "minute": 0 })
	assert_bool(dace.is_available_now()).is_true()
	Clock.apply_snapshot({ "year": 2001, "month": 1, "day": 1, "hour": 10, "minute": 0 })
	assert_bool(dace.is_available_now()).is_false()


func test_butterfly_uses_clock_months() -> void:
	var bug: BugData = load("res://data/creatures/common_butterfly.tres")
	assert_bool(bug.is_available(3, 8)).is_true()
	assert_bool(bug.is_available(1, 8)).is_false()
	assert_bool(bug.is_available(6, 19)).is_false()
	Clock.apply_snapshot({ "year": 2001, "month": 6, "day": 1, "hour": 10, "minute": 0 })
	assert_bool(bug.is_available_now()).is_true()
	Clock.apply_snapshot({ "year": 2001, "month": 1, "day": 1, "hour": 10, "minute": 0 })
	assert_bool(bug.is_available_now()).is_false()
