extends Node

## Renders the Mabel talk: the greeting line first, then (after advancing) the
## choice window. Run headed:
##   Godot --path . res://scenes/dev/capture_choice_window.tscn

const OUT_GREET := "res://recordings/choice_window_greet.png"
const OUT_MENU := "res://recordings/choice_window.png"


func _ready() -> void:
	await get_tree().process_frame
	var bg := ColorRect.new()
	bg.color = Color(0.30, 0.45, 0.28)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var overlay: Node = load("res://scenes/ui/dialogue_overlay.tscn").instantiate()
	add_child(overlay)
	await get_tree().process_frame

	var data := DialogueData.from_json_file("res://data/dialogue/mabel_menu.json")
	var ctx := DialogueContext.new()
	ctx.speaker_name = "Mabel"
	overlay.call("play", data, ctx)

	for _i in 120:
		await get_tree().process_frame
	_shot(OUT_GREET)

	## advance past the greeting line → choices appear
	var runner = overlay.call("runner")
	if runner != null:
		runner.advance()
	for _i in 90:
		await get_tree().process_frame
	_shot(OUT_MENU)

	get_tree().quit()


func _shot(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("wrote ", path)
