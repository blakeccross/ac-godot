extends Control

## Dev harness: open each menu overlay in turn and screenshot it to
## user://menu_survey_<name>.png, for side-by-side checks against the original.
##
##   $GODOT_BIN --path . res://scenes/dev/menu_survey.tscn

const SHOTS := [
	["name_entry", "res://scenes/ui/name_entry_overlay.tscn"],
	["catalog", "res://scenes/ui/catalog_overlay.tscn"],
	["map", "res://scenes/ui/map_overlay.tscn"],
	["pause", "res://scenes/ui/pause_overlay.tscn"],
]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.3, 0.55, 0.25)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	Game.player_name = "Nintendo"
	Game.town_name = "Villager"
	Game.inventory.set_wallet(12345)
	Game.inventory.add(ItemCatalog.get_item(&"apple"), 3)
	for shot: Array in SHOTS:
		var ui: CanvasLayer = load(shot[1]).instantiate()
		add_child(ui)
		await get_tree().process_frame
		match shot[0]:
			"name_entry": ui.open("Folder")
			"map": ui.open(true)
			_: ui.open()
		await get_tree().create_timer(0.5).timeout
		get_viewport().get_texture().get_image().save_png("user://menu_survey_%s.png" % shot[0])
		print("menu_survey: wrote ", shot[0])
		ui.queue_free()
		await get_tree().process_frame
	get_tree().quit()
