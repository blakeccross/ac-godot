extends GdUnitTestSuite

## Letter composition (`m_board_ovl.c` WRITE mode, `m_address_ovl.c`, `m_editor_ovl.c`)
## and the Museum fossil-mail path (`m_museum.c`).

const ADDRESS := preload("res://scenes/ui/letter_address_overlay.tscn")
const PAPER_PICKER := preload("res://scenes/ui/letter_paper_picker_overlay.tscn")
const WRITER := preload("res://scenes/ui/letter_writer_overlay.tscn")


func before_test() -> void:
	Game.reset_session()


func after_test() -> void:
	Game.reset_session()


func _meet(id: StringName) -> void:
	Game.villagers.get_or_create(id).record_talk("day1")


func test_address_book_lists_museum_and_only_met_villagers() -> void:
	_meet(&"filbert")
	var overlay: Node = auto_free(ADDRESS.instantiate())
	add_child(overlay)
	overlay.open()
	var entries: Array = overlay.get("_entries")
	var ids: Array = entries.map(func(e: Dictionary) -> StringName: return e.get("id"))
	assert_array(ids).contains([PostUse.MUSEUM_RECIPIENT_ID, &"filbert"])
	assert_bool(ids.has(&"rolf")).is_false()


func _writer() -> Node:
	var w: Node = auto_free(WRITER.instantiate())
	add_child(w)
	return w


func test_typing_appends_to_current_line_and_wraps() -> void:
	var w := _writer()
	w.open({"id": "filbert", "name": "Filbert"}, 5)
	assert_bool(w.is_open()).is_true()
	for i in 5:
		w.call("_type", "a")
	var lines: PackedStringArray = w.get("_lines")
	assert_int(lines.size()).is_equal(1)
	assert_str(lines[0]).is_equal("aaaaa")


func test_line_cap_refuses_to_wrap_past_six_lines() -> void:
	var w := _writer()
	w.open({"id": "filbert", "name": "Filbert"}, 0)
	## Explicit Enter always starts a new line up to the cap...
	for i in 5:
		w.call("_newline")
	var lines: PackedStringArray = w.get("_lines")
	assert_int(lines.size()).is_equal(6)
	w.call("_newline")
	lines = w.get("_lines")
	assert_int(lines.size()).is_equal(6)
	## ...and once the 6th line is itself too wide to fit another character, typing
	## refuses to wrap into a nonexistent 7th line rather than dropping the 6th line's
	## content.
	var wide := "wide "
	for i in 40:
		wide += "wide "
	w.set("_lines", PackedStringArray(["", "", "", "", "", wide]))
	w.call("_type", "x")
	lines = w.get("_lines")
	assert_int(lines.size()).is_equal(6)
	assert_str(lines[5]).is_equal(wide)


func test_save_creates_mail_with_body_paper_and_auto_header_footer() -> void:
	Game.player_name = "Nintendo"
	Game.inventory.clear()
	var w := _writer()
	w.open({"id": "filbert", "name": "Filbert"}, 12)
	w.call("_type", "h")
	w.call("_type", "i")
	w.call("_resolve_prompt", 0)
	assert_bool(w.is_open()).is_false()
	var mail: MailData = Game.inventory.mail_at(0)
	assert_that(mail).is_not_null()
	assert_str(mail.body).is_equal("hi")
	assert_int(mail.paper_type).is_equal(12)
	assert_str(mail.header).is_equal("Dear Filbert,")
	assert_str(mail.footer).is_equal("Nintendo")
	assert_str(mail.recipient_name).is_equal("Filbert")
	assert_bool(mail.is_sendable()).is_true()


func test_discard_leaves_slot_empty() -> void:
	Game.inventory.clear()
	var w := _writer()
	w.open({"id": "filbert", "name": "Filbert"}, 0)
	w.call("_type", "x")
	w.call("_resolve_prompt", 2)
	assert_bool(w.is_open()).is_false()
	assert_int(Game.inventory.count_mail()).is_equal(0)


func test_keep_editing_returns_to_editor_with_draft_intact() -> void:
	var w := _writer()
	w.open({"id": "filbert", "name": "Filbert"}, 0)
	w.call("_type", "x")
	w.call("_open_prompt")
	w.call("_resolve_prompt", 1)
	assert_bool(w.is_open()).is_true()
	var lines: PackedStringArray = w.get("_lines")
	assert_str(lines[0]).is_equal("x")


func test_present_attaches_hand_item_and_clears_the_pocket_slot() -> void:
	Game.inventory.clear()
	Game.player_name = "Nintendo"
	var w := _writer()
	w.open({"id": "filbert", "name": "Filbert"}, 0)
	w.call("_resolve_prompt", 0)
	var mail: MailData = Game.inventory.mail_at(0)
	assert_that(mail).is_not_null()

	Game.inventory.add(ItemCatalog.get_item(&"apple"), 1)
	Game.inventory.pick_hand(0)
	assert_int(Game.inventory.hand_index).is_equal(0)

	var overlay: Node = auto_free(load("res://scenes/ui/inventory_overlay.tscn").instantiate())
	add_child(overlay)
	overlay.call("_present_on_mail", 0)

	assert_str(String(mail.present_item_id)).is_equal("apple")
	assert_int(Game.inventory.hand_index).is_equal(-1)
	assert_bool(Game.inventory.slot_at(0).is_empty()).is_true()


## `mTG_present_proc`'s other direction: an empty hand on an already-presented letter
## takes the gift back out instead of attaching another one.
func test_present_tag_offered_both_ways_and_take_back_returns_item_to_pockets() -> void:
	Game.inventory.clear()
	Game.player_name = "Nintendo"
	var w := _writer()
	w.open({"id": "filbert", "name": "Filbert"}, 0)
	w.call("_resolve_prompt", 0)
	var mail: MailData = Game.inventory.mail_at(0)
	mail.present_item_id = &"apple"

	var overlay: Node = auto_free(load("res://scenes/ui/inventory_overlay.tscn").instantiate())
	add_child(overlay)
	overlay.call("open")
	overlay.set("_focus_mail", true)
	Game.inventory.select_mail(0)
	overlay.call("_activate_mail_cursor")
	assert_that(overlay.get("_tag_choices")).is_equal(PackedStringArray(["Present", "Discard"]))

	overlay.call("_present_on_mail", 0)
	assert_str(String(mail.present_item_id)).is_equal("")
	assert_int(Game.inventory.count_of(&"apple")).is_equal(1)
	assert_int(Game.inventory.hand_index).is_equal(-1)


func test_present_tag_hidden_when_hand_full_and_letter_already_has_a_gift() -> void:
	Game.inventory.clear()
	var w := _writer()
	w.open({"id": "filbert", "name": "Filbert"}, 0)
	w.call("_resolve_prompt", 0)
	var mail: MailData = Game.inventory.mail_at(0)
	mail.present_item_id = &"apple"

	Game.inventory.add(ItemCatalog.get_item(&"net"), 1)

	var overlay: Node = auto_free(load("res://scenes/ui/inventory_overlay.tscn").instantiate())
	add_child(overlay)
	overlay.call("open") ## clears any stale hand state, same as the real "Write" flow
	Game.inventory.pick_hand(0)
	overlay.set("_focus_mail", true)
	Game.inventory.select_mail(0)
	overlay.call("_activate_mail_cursor")
	assert_that(overlay.get("_tag_choices")).is_equal(PackedStringArray(["Discard"]))


func test_museum_letter_with_fossil_queues_farway_and_skips_the_desk() -> void:
	Game.reset_session()
	Game.inventory.clear()
	Game.post.clear()
	Game.farway.clear()

	var w := _writer()
	w.open({"id": String(PostUse.MUSEUM_RECIPIENT_ID), "name": PostUse.MUSEUM_RECIPIENT_NAME}, 0)
	w.call("_resolve_prompt", 0)
	var idx: int = Game.inventory.sendable_mail_indices()[0]
	var mail: MailData = Game.inventory.mail_at(idx)
	assert_str(String(mail.recipient_id)).is_equal("museum")

	mail.present_item_id = &"fossil"

	var msg: String = PostUse.send_mail_at(idx)
	assert_str(msg).contains("Museum")
	assert_int(Game.farway.in_transit_count()).is_equal(1)
	assert_int(Game.post.get_keep_mail_sum()).is_equal(0)
	assert_int(Game.inventory.count_mail()).is_equal(0)


func test_museum_letter_without_a_present_refuses_to_send() -> void:
	Game.inventory.clear()
	var w := _writer()
	w.open({"id": String(PostUse.MUSEUM_RECIPIENT_ID), "name": PostUse.MUSEUM_RECIPIENT_NAME}, 0)
	w.call("_resolve_prompt", 0)
	var idx: int = Game.inventory.sendable_mail_indices()[0]
	var msg: String = PostUse.send_mail_at(idx)
	assert_str(msg).contains("fossil")
	assert_int(Game.inventory.count_mail()).is_equal(1)
