extends GdUnitTestSuite

## Letter-reading board overlay (`m_board_ovl.c`, `mSM_BD_OPEN_READ`).

const READER := preload("res://scenes/ui/letter_reader_overlay.tscn")


func _reader() -> Node:
	var r: Node = auto_free(READER.instantiate())
	add_child(r)
	return r


func _received_mail(paper_type: int = 0) -> MailData:
	var mail := MailData.new()
	mail.font = MailData.LetterFont.RECV
	mail.sender_name = "Copper"
	mail.header = "Dear Nintendo,"
	mail.body = "Welcome to town!"
	mail.footer = "Copper"
	mail.paper_type = paper_type
	return mail


func test_open_shows_paper_art_and_ink_color_for_paper_type() -> void:
	var r := _reader()
	var mail := _received_mail(9)
	r.open(mail)
	assert_bool(r.is_open()).is_true()
	assert_object(r._paper.texture).is_equal(LetterChrome.paper_texture(9))
	assert_bool(r._header.has_theme_color_override("font_color")).is_true()
	assert_that(r._header.get_theme_color("font_color")).is_equal(LetterChrome.ink_color(9))


func test_open_populates_header_body_footer_from_mail() -> void:
	var r := _reader()
	var mail := _received_mail()
	r.open(mail)
	assert_str(r._header.text).is_equal(mail.header)
	assert_str(r._body.text).is_equal(mail.body)
	assert_str(r._footer.text).is_equal(mail.footer)


func test_open_marks_a_received_letter_read_exactly_once() -> void:
	var r := _reader()
	var mail := _received_mail()
	assert_int(mail.font).is_equal(MailData.LetterFont.RECV)
	r.open(mail)
	assert_int(mail.font).is_equal(MailData.LetterFont.RECV_READ)


func test_close_emits_closed_and_can_reopen() -> void:
	var r := _reader()
	var mail := _received_mail()
	r.open(mail)
	var closed_mail: Array = []
	r.closed.connect(func(m: MailData) -> void: closed_mail.append(m))
	r.close()
	await get_tree().create_timer(0.4).timeout
	assert_bool(r.is_open()).is_false()
	assert_array(closed_mail).contains([mail])

	var mail2 := _received_mail(3)
	r.open(mail2)
	assert_bool(r.is_open()).is_true()
	assert_str(r._header.text).is_equal(mail2.header)


func test_ignores_open_while_already_open() -> void:
	var r := _reader()
	var mail := _received_mail()
	r.open(mail)
	var mail2 := _received_mail(5)
	r.open(mail2)
	assert_str(r._header.text).is_equal(mail.header)


func test_ink_color_and_paper_texture_clamp_out_of_range_paper_type() -> void:
	assert_that(LetterChrome.ink_color(999)).is_equal(LetterChrome.ink_color(63))
	assert_object(LetterChrome.paper_texture(-5)).is_equal(LetterChrome.paper_texture(0))
