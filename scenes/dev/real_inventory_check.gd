extends Node3D

## Loads the REAL field + HUD (not a standalone overlay instance, unlike
## `inventory_proof.gd`) and opens pockets the way the player actually reaches it —
## for bugs that only show up wired into the live HUD, not a freshly instantiated overlay.
##
##   $GODOT_BIN --path . res://scenes/dev/real_inventory_check.tscn

func _ready() -> void:
	await _run()
	get_tree().quit()


func _run() -> void:
	Clock.paused = true
	Game.world_mode = WorldData.Mode.GENERATED
	Game.world_seed = 42

	var world: Node3D = load("res://scenes/world/world.tscn").instantiate() as Node3D
	add_child(world)
	for _i in 30:
		await get_tree().process_frame

	var overlay: Node = get_tree().get_first_node_in_group("inventory_ui")
	if overlay == null:
		print("real_inventory_check: no live InventoryOverlay found in the HUD")
		return
	overlay.call("open")
	await get_tree().create_timer(0.6).timeout

	var player_name: Label = overlay.get_node("%PlayerName") as Label
	var town_name: Label = overlay.get_node("%TownName") as Label
	print("PlayerName text=%s visible=%s" % [player_name.text, player_name.visible])
	print("TownName text=%s visible=%s" % [town_name.text, town_name.visible])

	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("user://real_inventory_check.png")
	print("real_inventory_check: wrote screenshot")

	overlay.call("_show_page", 0) # SideTab.FISH
	await get_tree().create_timer(0.4).timeout
	img = get_viewport().get_texture().get_image()
	img.save_png("user://real_inventory_check_fish.png")
	print("real_inventory_check: wrote fish screenshot")

	overlay.call("_show_page", 2) # SideTab.BUG
	await get_tree().create_timer(0.4).timeout
	img = get_viewport().get_texture().get_image()
	img.save_png("user://real_inventory_check_bug.png")
	print("real_inventory_check: wrote bug screenshot")
