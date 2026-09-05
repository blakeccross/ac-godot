extends Node3D

## Renders the player house and saves door-facing PNGs for visual audit.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . res://scenes/dev/capture_player_house.tscn
##
## Output: `res://recordings/player_house/*.png`

const OUT_DIR := "res://recordings/player_house"
const HOUSE_ID := &"obj_s_myhome1"

@onready var _camera: Camera3D = $Camera3D
@onready var _house_host: Node3D = $House


func _ready() -> void:
	Clock.paused = true
	Game.reset_session()
	get_viewport().size = Vector2i(960, 540)
	get_tree().root.size = Vector2i(960, 540)
	call_deferred("_run")


func _run() -> void:
	if FieldCatalog.mesh_paths(HOUSE_ID).is_empty():
		push_error("Missing player house assets — run tools/build_assets.py first")
		get_tree().quit(1)
		return
	if GeneratedVisual.attach(_house_host, HOUSE_ID) == null:
		push_error("Failed to attach %s" % HOUSE_ID)
		get_tree().quit(1)
		return

	## Daytime so window panes stay black (off), door texture is readable.
	Clock.apply_snapshot({"year": 2001, "month": 7, "day": 15, "hour": 12, "minute": 0})
	GeneratedVisual.refresh(_house_host, HOUSE_ID)
	_dump_visual(_house_host)

	var focus: Vector3 = _house_host.global_position + Vector3(0.0, 1.6, 0.0)
	_camera.current = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	print("=== PLAYER HOUSE CAPTURE ===")

	## Door faces the porch diagonal (SW in bind pose); shoot from that side.
	var shots: Array[Dictionary] = [
		{
			"name": "door_front",
			"pos": focus + Vector3(-3.2, 1.0, 3.8),
			"look": focus + Vector3(0.0, 0.4, 0.0),
		},
		{
			"name": "door_close",
			"pos": focus + Vector3(-1.6, 0.6, 2.2),
			"look": focus + Vector3(-0.4, 0.2, 0.4),
		},
		{
			"name": "three_quarter",
			"pos": focus + Vector3(-4.5, 2.2, 2.0),
			"look": focus + Vector3(0.0, 0.8, 0.0),
		},
		{
			"name": "night_door",
			"pos": focus + Vector3(-3.2, 1.0, 3.8),
			"look": focus + Vector3(0.0, 0.4, 0.0),
			"hour": 21,
		},
	]
	for shot: Dictionary in shots:
		Clock.apply_snapshot(
			{
				"year": 2001,
				"month": 7,
				"day": 15,
				"hour": int(shot.get("hour", 12)),
				"minute": 0,
			}
		)
		GeneratedVisual.refresh(_house_host, HOUSE_ID)
		_camera.position = shot["pos"]
		_camera.look_at(shot["look"])
		await _save("%s/%s.png" % [OUT_DIR, shot["name"]])
		print("  wrote ", shot["name"])

	print("shots in ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()


func _dump_visual(host: Node) -> void:
	print("--- visual tree ---")
	_dump_node(host, 0)


func _dump_node(node: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	var extra := ""
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		extra = " mesh=%s skin=%s surfaces=%d" % [
			mi.mesh,
			mi.skin != null,
			mi.mesh.get_surface_count() if mi.mesh else 0,
		]
		if mi.mesh:
			var aabb: AABB = mi.get_aabb()
			extra += " aabb=%s" % aabb
			for i: int in mi.mesh.get_surface_count():
				var mat: Material = mi.get_active_material(i)
				var label := ""
				if mat:
					label = mat.resource_name
					if mat is StandardMaterial3D:
						var std := mat as StandardMaterial3D
						label += " transp=%d albedo=%s" % [std.transparency, std.albedo_color]
				print("%s  surf%d: %s" % [pad, i, label])
	elif node is Skeleton3D:
		extra = " bones=%d" % (node as Skeleton3D).get_bone_count()
	print("%s%s (%s)%s" % [pad, node.name, node.get_class(), extra])
	for child in node.get_children():
		_dump_node(child, depth + 1)


func _save(path: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(path)
