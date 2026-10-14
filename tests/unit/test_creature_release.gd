class_name TestCreatureRelease
extends GdUnitTestSuite

## Letting a bug or fish go from the pockets (`mTG_release_proc`, `ac_gyo_release`).

const GX := FieldCatalog.GX_TO_METERS


## Water for z past `edge_gx`, facing +z.
func _lake(edge_gx: float) -> Callable:
	return func(at: Vector3) -> bool: return at.z / GX >= edge_gx


func test_water_ahead_needs_its_corners_wet_too() -> void:
	## Steps are 10 GX; a step only counts with the four ±12 GX corners also in water.
	var found: Variant = CreatureRelease.search_water(_lake(35.0), Vector3.ZERO, 0.0)
	assert_object(found).is_not_null()
	assert_float((found as Vector3).z / GX).is_equal_approx(50.0, 0.01)
	## Beyond 120 GX there is nothing to throw at.
	assert_object(CreatureRelease.search_water(_lake(200.0), Vector3.ZERO, 0.0)).is_null()
	## Facing away from the lake.
	assert_object(CreatureRelease.search_water(_lake(35.0), Vector3.ZERO, PI)).is_null()


func test_a_far_throw_crosses_in_sixty_ticks() -> void:
	var vel: Vector3 = CreatureRelease.launch_velocity(Vector3.ZERO, Vector3(0.0, -10.0, 90.0))
	## dist / 60 / 0.5 across, (dy + 450) / 60 up.
	assert_float(vel.z).is_equal_approx(3.0, 0.0001)
	assert_float(vel.y).is_equal_approx(440.0 / 60.0, 0.0001)
	var pos := Vector3.ZERO
	for i: int in 60:
		var moved: Array[Vector3] = CreatureRelease.step(pos, vel)
		pos = moved[0]
		vel = moved[1]
	assert_float(pos.z).is_equal_approx(90.0, 0.001)
	## A near throw (inside one unit) is a short lob.
	var near: Vector3 = CreatureRelease.launch_velocity(Vector3.ZERO, Vector3(0.0, 0.0, 30.0))
	assert_float(near.z).is_equal_approx(2.5, 0.0001)
	assert_float(near.y).is_equal_approx(30.0 * 0.18, 0.0001)


func test_it_shrinks_away_past_140_ticks() -> void:
	assert_float(CreatureRelease.shrink(140)).is_equal(1.0)
	assert_float(CreatureRelease.shrink(141)).is_equal_approx(0.89, 0.0001)
	assert_float(CreatureRelease.shrink(160)).is_less(0.5)


func test_bugs_go_anywhere_outdoors_fish_only_into_water() -> void:
	var bug: ItemData = BugData.new()
	bug.category = ItemData.Category.BUG
	var fish: ItemData = FishData.new()
	fish.category = ItemData.Category.FISH
	assert_bool(CreatureRelease.can_release(bug, true, false)).is_true()
	assert_bool(CreatureRelease.can_release(bug, false, false)).is_false()
	assert_bool(CreatureRelease.can_release(fish, true, false)).is_false()
	assert_bool(CreatureRelease.can_release(fish, true, true)).is_true()


func test_thrown_fish_splashes_down_and_leaves_a_shadow() -> void:
	var fish: FishData = ItemCatalog.get_item(&"crucian_carp") as FishData
	assert_object(fish).is_not_null()
	var school := FishSchool.new()
	var water := Vector3(0.0, -10.0, 90.0) * GX
	var node := (load(FishRelease.SCENE_PATH) as PackedScene).instantiate() as FishRelease
	node.fish = fish
	node._vel_gx = CreatureRelease.launch_velocity(Vector3.ZERO, water / GX)
	node._yaw = 0.0
	node.is_water = _lake(60.0)
	node.water_y = func(_at: Vector3) -> float: return water.y
	node.school = school
	add_child(node)
	var ticks: int = 0
	while node.exist and ticks < CreatureRelease.LIFE + 2:
		node.tick()
		ticks += 1
	assert_bool(node.exist).is_false()
	assert_int(ticks).is_less(CreatureRelease.LIFE)
	assert_int(school.puffs.size()).is_equal(1)
	assert_float(school.puffs[0].position.z / GX).is_greater(60.0)
