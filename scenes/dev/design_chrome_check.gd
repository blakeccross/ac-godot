extends Control

## Dev harness: open the design editor + design list overlays with the real
## `des_win_*` window chrome and screenshot both.
##
##   $GODOT_BIN --path . res://scenes/dev/design_chrome_check.tscn

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.3, 0.55, 0.25)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	if Game.designs == null:
		print("design_chrome_check: Game.designs is null, aborting")
		get_tree().quit()
		return

	var list_overlay: CanvasLayer = load("res://scenes/ui/design_list_overlay.tscn").instantiate()
	add_child(list_overlay)
	var editor: CanvasLayer = load("res://scenes/ui/design_editor_overlay.tscn").instantiate()
	add_child(editor)

	await get_tree().process_frame
	list_overlay.open("manage")
	await get_tree().create_timer(0.3).timeout
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("user://design_chrome_1_list.png")
	print("design_chrome_check: wrote 1_list")
	list_overlay.close(-1)

	await get_tree().process_frame
	editor.open(0)
	editor._grid_on = true
	editor._mode = editor.Mode.TOOL
	editor._tool_row = editor.Tool.NURI
	editor._refresh()
	await get_tree().create_timer(0.3).timeout
	img = get_viewport().get_texture().get_image()
	img.save_png("user://design_chrome_2_editor.png")
	print("design_chrome_check: wrote 2_editor")

	print("design_chrome_check: done")
	get_tree().quit()
