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

	await get_tree().process_frame
	address.open()
	await get_tree().create_timer(0.3).timeout
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("user://letter_writer_1_address.png")
	print("letter_writer_check: wrote 1_address")
	address.close()

	await get_tree().process_frame
	picker.open({"id": "filbert", "name": "Filbert"})
	picker._sel = 20
	picker._refresh()
	await get_tree().create_timer(0.3).timeout
	img = get_viewport().get_texture().get_image()
	img.save_png("user://letter_writer_2_paper.png")
	print("letter_writer_check: wrote 2_paper")
	picker.close()

	await get_tree().process_frame
	writer.open({"id": "filbert", "name": "Filbert"}, 20)
	for ch in "Hi Filbert! Hope you are having a wonderful day today.":
		if ch == " ":
			writer._type(" ")
		else:
			writer._type(ch)
	await get_tree().create_timer(0.3).timeout
	img = get_viewport().get_texture().get_image()
	img.save_png("user://letter_writer_3_compose.png")
	print("letter_writer_check: wrote 3_compose")

	writer._open_prompt()
	await get_tree().create_timer(0.3).timeout
	img = get_viewport().get_texture().get_image()
	img.save_png("user://letter_writer_4_prompt.png")
	print("letter_writer_check: wrote 4_prompt")

	print("letter_writer_check: done")
	get_tree().quit()
