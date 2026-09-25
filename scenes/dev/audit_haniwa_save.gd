extends Node3D

## Live check of the house gyroid's Save flow in the real field: stands the player in front of
## `player_haniwa` facing it, talks with real A presses (Save → That's right!), then logs the scripted
## walk to the door and screenshots each beat. The flow ends in `Game.return_to_title`, which
## SAVES — back up `user://save.json` before running this.
##
##   $GODOT_BIN --path . res://scenes/dev/audit_haniwa_save.tscn
##
## Output: `res://recordings/haniwa/save_*.png`

const OUT_DIR := "res://recordings/haniwa"

var _shots: int = 0


func _ready() -> void:
	get_viewport().size = Vector2i(960, 540)
	get_tree().root.size = Vector2i(960, 540)
	_run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	Clock.paused = true
	Game.world_mode = WorldData.Mode.GENERATED
	Game.world_seed = 4242
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate() as Node3D
	add_child(world)
	for _i in 30:
		await get_tree().process_frame
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	var gyroid: Node3D = null
	for n: Node in get_tree().get_nodes_in_group("haniwa"):
		if n.name == "player_haniwa":
			gyroid = n as Node3D
	if player == null or gyroid == null:
		print("AUDIT: missing player=", player, " gyroid=", gyroid)
		get_tree().quit()
		return
	## One unit south of the gyroid, facing it (north).
	player.global_position = gyroid.global_position + Vector3(0.0, 0.0, 2.0)
	player.call("set_facing", PI)
	for _i in 20:
		await get_tree().physics_frame
	print("AUDIT gyroid=", gyroid.global_position, " player=", player.global_position)
	## The real path: A through the player's facing probe (`_try_interact` → `_run_interact`).
	_press_a()
	for _i in 30:
		await get_tree().process_frame
	var ui: Node = get_tree().get_first_node_in_group("dialogue_ui")
	print("AUDIT talk opened=", ui != null and bool(ui.call("is_open")))
	var presses: int = 0
	var shot_menu: bool = false
	while ui != null and bool(ui.call("is_open")) and presses < 60:
		await get_tree().create_timer(0.35).timeout
		var runner: DialogueRunner = ui.call("runner") as DialogueRunner
		if runner != null and runner.waiting_choice and not shot_menu:
			await get_tree().create_timer(0.4).timeout
			await _shot("menu")
			shot_menu = true
		print("AUDIT line: ", runner.line.replace("\n", " ") if runner != null else "")
		_press_a()
		presses += 1
	print("AUDIT talk closed after ", presses, " presses")
	var start := Time.get_ticks_msec()
	var last_log := 0
	while is_inside_tree() and is_instance_valid(player) and Time.get_ticks_msec() - start < 6000:
		await get_tree().physics_frame
		if not is_inside_tree():
			return
		var t := Time.get_ticks_msec() - start
		if t - last_log >= 250:
			last_log = t
			var off: Vector3 = (player.global_position - gyroid.global_position) / FieldCatalog.GX_TO_METERS
			print("AUDIT t=%d walk=%s door=%s off_gx=(%.0f, %.0f)" % [
				t, player.call("is_demo_walking"), player.call("is_door_entering"), off.x, off.z
			])
			if t in [500, 1000] or (t >= 1500 and _shots < 4):
				await _shot("walk_%d" % t)
	print("AUDIT done")


func _press_a() -> void:
	var ev := InputEventAction.new()
	ev.action = &"interact"
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = &"interact"
	up.pressed = false
	Input.parse_input_event(up)


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("%s/save_%s.png" % [OUT_DIR, tag])
		_shots += 1
		print("AUDIT shot ", tag)
