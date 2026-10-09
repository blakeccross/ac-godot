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


func test_title_card_opens_once_and_closes_the_same_day() -> void:
	## `title_fade` / `mEv_set_keep`.
	var keep: Dictionary = {}
	assert_int(EventTitle.due(&"groundhog_day", true, keep, "2002-02-02")).is_equal(1)
	keep["groundhog_day"] = "2002-02-02"
	assert_int(EventTitle.due(&"groundhog_day", true, keep, "2002-02-02")).is_equal(0)
	assert_int(EventTitle.due(&"groundhog_day", false, keep, "2002-02-02")).is_equal(-1)
	## Kept from another day: dropped without a closing card.
	assert_int(EventTitle.due(&"groundhog_day", false, keep, "2002-02-03")).is_equal(0)
	assert_bool(keep.has("groundhog_day")).is_false()
	## Visitors have no card.
	assert_int(EventTitle.due(&"kk_slider", true, {}, "x")).is_equal(0)


func test_title_messages_follow_get_title_no() -> void:
	assert_int(EventTitle.message(&"groundhog_day", true)).is_equal(0x1743 + 14)
	assert_int(EventTitle.message(&"groundhog_day", false)).is_equal(0x1799 + 14)
	assert_int(EventTitle.message(&"fireworks_show", true)).is_equal(0x1743)
	assert_object(DialogueCatalog.conversation(&"msg_5969")).is_not_null()
