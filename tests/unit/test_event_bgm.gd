class_name TestEventBgm
extends GdUnitTestSuite

## `mBGMFieldSchedEv`: event music by acre.

const SHRINE := Vector2i(3, 2)
const POOL := Vector2i(4, 5)


func _blocks(kind: String) -> Vector2i:
	match kind:
		"shrine":
			return SHRINE
		"pool":
			return POOL
	return Vector2i(-1, -1)


func _only(id: StringName) -> Callable:
	return func(e: StringName) -> bool: return e == id


func test_the_festival_plays_full_on_its_acre_and_half_beside_it() -> void:
	var on: Dictionary = EventBgm.pick(_only(&"cherry_blossom_festival"), SHRINE, _blocks)
	assert_str(String(on["id"])).is_equal(String(BgmCatalog.id_for_num(56)))
	assert_float(float(on["db"])).is_equal(0.0)
	var beside: Dictionary = EventBgm.pick(_only(&"cherry_blossom_festival"), SHRINE + Vector2i(1, 0), _blocks)
	assert_float(float(beside["db"])).is_equal_approx(-6.02, 0.01)
	## Diagonal or further: the field's own music.
	assert_bool(EventBgm.pick(_only(&"cherry_blossom_festival"), SHRINE + Vector2i(1, 1), _blocks).is_empty()).is_true()


func test_halloween_is_heard_everywhere() -> void:
	var anywhere: Dictionary = EventBgm.pick(_only(&"halloween"), Vector2i(1, 6), _blocks)
	assert_str(String(anywhere["id"])).is_equal(String(BgmCatalog.id_for_num(53)))


func test_groundhog_day_quiets_the_shrine() -> void:
	## 251 is not a sequence: the shrine acre goes quiet.
	var on: Dictionary = EventBgm.pick(_only(&"groundhog_day"), SHRINE, _blocks)
	assert_str(String(on["id"])).is_equal(String(EventBgm.QUIET))
	assert_bool(EventBgm.pick(_only(&"groundhog_day"), POOL, _blocks).is_empty()).is_true()


func test_no_event_no_override() -> void:
	assert_bool(EventBgm.pick(func(_e: StringName) -> bool: return false, SHRINE, _blocks).is_empty()).is_true()
