class_name TestResources
extends GdUnitTestSuite


func test_item_catalog() -> void:
	var apple: ItemData = load("res://data/items/apple.tres")
	assert_that(apple).is_not_null()
	assert_that(apple.id).is_equal(&"apple")
	assert_int(apple.max_stack).is_equal(1)
	assert_that(apple.category).is_equal(ItemData.Category.FRUIT)


func test_furniture_extends_item() -> void:
	var chair: FurnitureData = load("res://data/furniture/wood_chair.tres")
	assert_that(chair).is_not_null()
	assert_that(chair.indoor).is_true()
	assert_that(chair.footprint).is_equal(Vector2i(1, 1))


func test_boy_looks_schedule() -> void:
	var schedule: ScheduleData = load("res://data/schedules/pip_weekday.tres")
	assert_that(schedule.activity_at(7)).is_equal(&"sleep")
	assert_that(schedule.activity_at(8)).is_equal(&"in_house")
	assert_that(schedule.activity_at(9)).is_equal(&"field")
	assert_that(schedule.activity_at(12)).is_equal(&"in_house")
	assert_that(schedule.activity_at(14)).is_equal(&"field")
	assert_that(schedule.activity_at(20)).is_equal(&"in_house")
	assert_that(schedule.activity_at(22)).is_equal(&"sleep")


func test_acre_grid_defaults() -> void:
	var acre: AcreData = load("res://data/acres/plot_a.tres")
	assert_int(acre.columns).is_equal(16)
	assert_int(acre.rows).is_equal(16)
	assert_int(acre.water_cells.size()).is_equal(4)


func test_villager_points_at_schedule() -> void:
	var pip: VillagerData = load("res://data/villagers/pip.tres")
	assert_that(pip.display_name).is_equal("Pip")
	assert_that(pip.schedule).is_not_null()
	assert_that(pip.schedule.activity_at(9)).is_equal(&"field")
