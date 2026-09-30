extends Control

## Dev harness: walk the full letter-writing flow (address book -> paper picker ->
## composition board) and screenshot each step.
##
##   $GODOT_BIN --path . res://scenes/dev/letter_writer_check.tscn

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.3, 0.55, 0.25)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	Game.player_name = "Nintendo"
	Game.villagers.get_or_create(&"filbert").record_talk("day1")

	var address: CanvasLayer = load("res://scenes/ui/letter_address_overlay.tscn").instantiate()
	add_child(address)
	var picker: CanvasLayer = load("res://scenes/ui/letter_paper_picker_overlay.tscn").instantiate()
	add_child(picker)
	var writer: CanvasLayer = load("res://scenes/ui/letter_writer_overlay.tscn").instantiate()
	add_child(writer)

	for v: StringName in [&"filbert", &"rolf", &"bitty", &"tank"]:
		Game.villagers.get_or_create(v).record_talk("day1")
	await get_tree().process_frame
	picker.open()
	picker._sel = 20
	picker._refresh()
	await get_tree().create_timer(0.3).timeout
	_shot("1_paper")
	picker._confirm()
	await get_tree().create_timer(0.3).timeout
	_shot("2_address_title")
	address._choosing = true
	address._sel = 1
	address._page = 1
	address._screen.queue_redraw()
	await get_tree().create_timer(0.2).timeout
	_shot("3_address")
	address._confirm()
	for ch in "Hi Filbert! Hope you are having a wonderful day today. See you at the museum soon!":
		writer._type(ch)
	await get_tree().create_timer(0.6).timeout
	_shot("4_compose")
	writer._open_prompt()
	writer._promptbox.handle_key(_key(KEY_SPACE))
	await get_tree().create_timer(0.3).timeout
	_shot("5_prompt")

	print("letter_writer_check: done")
	get_tree().quit()


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png("user://letter_writer_%s.png" % name)
	print("letter_writer_check: wrote ", name)


func _key(code: Key) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	return k
