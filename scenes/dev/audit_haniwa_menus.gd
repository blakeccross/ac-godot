extends Node3D

## Live check of the house gyroid's menus in the real field, driven with real key presses:
## Store an item (consign a pocket item at a price), Other things → About the door → Post
## pattern (door design), and Set message. Screenshots each overlay and the door. Does not
## save.
##
##   $GODOT_BIN --path . res://scenes/dev/audit_haniwa_menus.tscn
##
## Output: `res://recordings/haniwa/menu_*.png`

const OUT_DIR := "res://recordings/haniwa"


func _ready() -> void:
	get_viewport().size = Vector2i(960, 540)
	get_tree().root.size = Vector2i(960, 540)
	_run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	Clock.paused = true
	Clock.hour = 12
	Game.world_mode = WorldData.Mode.GENERATED
	Game.world_seed = 4242
	add_child(load("res://scenes/world/world.tscn").instantiate())
	for _i in 30:
		await get_tree().process_frame
	Game.inventory.add(ItemCatalog.get_item(&"apple"), 1)
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	var gyroid: Node3D = null
	for n: Node in get_tree().get_nodes_in_group("haniwa"):
		if n.name == "player_haniwa":
			gyroid = n as Node3D
	player.global_position = gyroid.global_position + Vector3(0.0, 0.0, 2.0)
	player.call("set_facing", PI)
	for _i in 10:
		await get_tree().physics_frame
	var ui: Node = get_tree().get_first_node_in_group("dialogue_ui")
	var inv_ui: Node = get_tree().get_first_node_in_group("inventory_ui")
	var house: House = Game.interiors.player_house()

	## 1. Store an item.
	await _key(&"interact")
	await _to_choice(ui)
	await _key(&"ui_down")
	await _key(&"interact")
	await _wait_for(func() -> bool: return bool(inv_ui.call("is_open")))
	print("MENU inventory open=", inv_ui.call("is_open"))
	## Hand the apple (pocket 0) over the first gyroid slot: pick it, move right ×5.
	await _key(&"inventory_quick_grab")
	for _i in Inventory.COLUMNS:
		await _key(&"ui_right")
	await _key(&"interact")        ## tag: Free / Set price / Display only
	await _shot("menu_store_tags")
	await _key(&"ui_down")
	await _key(&"interact")        ## Set price
	await _key(&"ui_left")         ## digit 3 (tens)… go to hundreds
	await _key(&"ui_left")
	await _key(&"ui_up")
	await _key(&"ui_up")           ## 200
	await _shot("menu_store_price")
	await _key(&"interact")
	print("MENU slot0=", HaniwaStore.item_at(house, 0), " apples in pockets=", Game.inventory.count_of(&"apple"))
	await _shot("menu_store_done")
	await _key(&"ui_cancel")
	await _wait_for(func() -> bool: return bool(ui.call("is_open")))
	var runner: DialogueRunner = ui.call("runner") as DialogueRunner
	print("MENU resumed line=", runner.line.replace("\n", " "))

	## 2. Other things → About the door → Post pattern.
	await _to_choice(ui)
	await _key(&"ui_down")
	await _key(&"ui_down")
	await _key(&"interact")        ## Other things
	await _to_choice(ui)
	await _key(&"interact")        ## About the door
	await _to_choice(ui)
	await _key(&"interact")        ## Post pattern
	var list_ui: Node = get_tree().get_first_node_in_group("design_list_ui")
	await _wait_for(func() -> bool: return bool(list_ui.call("is_open")))
	await _shot("menu_design_list")
	## The design list reads raw keys.
	await _raw_key(KEY_RIGHT)
	await _raw_key(KEY_SPACE)
	await _wait_for(func() -> bool: return bool(ui.call("is_open")))
	print("MENU door_original=", house.door_original)

	## 3. Other things → Set message.
	await _to_choice(ui)
	await _key(&"ui_down")
	await _key(&"ui_down")
	await _key(&"interact")        ## Other things
	await _to_choice(ui)
	await _key(&"ui_down")
	await _key(&"interact")        ## Set message
	var writer: Node = get_tree().get_first_node_in_group("letter_writer_ui")
	await _wait_for(func() -> bool: return bool(writer.call("is_open")))
	await _shot("menu_message")
	for c in "Hi":
		var ev := InputEventKey.new()
		ev.pressed = true
		ev.keycode = OS.find_keycode_from_string(c)
		ev.unicode = c.unicode_at(0)
		Input.parse_input_event(ev)
		await get_tree().create_timer(0.1).timeout
	await _raw_key(KEY_ESCAPE)
	await _raw_key(KEY_SPACE)      ## Save it
	await _wait_for(func() -> bool: return bool(ui.call("is_open")))
	print("MENU message=", house.haniwa_message.replace("\n", " | "))
	## Leave the talk, then look at the door.
	await _to_choice(ui)
	await _key(&"ui_down")
	await _key(&"ui_down")
	await _key(&"ui_down")
	await _key(&"interact")        ## Never mind
	while bool(ui.call("is_open")):
		await _key(&"interact")
	var cam: Camera3D = get_viewport().get_camera_3d()
	var door_house: Node3D = get_tree().root.find_child("player_house", true, false) as Node3D
	player.global_position = door_house.global_position + Vector3(2.4, 0.0, 2.4)
	for _i in 30:
		await get_tree().process_frame
	await _shot("menu_door")
	print("MENU done cam=", cam != null)
	get_tree().quit()


func _to_choice(ui: Node) -> void:
	for _i in 30:
		var r: DialogueRunner = ui.call("runner") as DialogueRunner
		if r != null and r.waiting_choice:
			await get_tree().create_timer(0.5).timeout
			return
		await _key(&"interact")
	print("MENU no choice reached")


func _wait_for(cond: Callable) -> void:
	for _i in 200:
		if cond.call():
			await get_tree().create_timer(0.3).timeout
			return
		await get_tree().process_frame


func _key(action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().create_timer(0.25).timeout


func _raw_key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = code
	Input.parse_input_event(ev)
	await get_tree().create_timer(0.3).timeout


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("%s/%s.png" % [OUT_DIR, tag])
