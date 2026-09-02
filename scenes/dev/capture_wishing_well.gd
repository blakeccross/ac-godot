extends Node3D

## Renders the wishing well on its shrine acre and saves PNGs for visual audit.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . res://scenes/dev/capture_wishing_well.tscn
##
## Output: `res://recordings/wishing_well/*.png`

const OUT_DIR := "res://recordings/wishing_well"

const ACRE_ID := &"grd_s_f_ko_2"
const WELL_ID := &"obj_s_shrine"

const SEASONS: Array[Dictionary] = [
	{ "name": "summer", "month": 7, "day": 15 },
	{ "name": "autumn", "month": 10, "day": 20 },
	{ "name": "winter", "month": 1, "day": 15 },
]

@onready var _camera: Camera3D = $Camera3D
@onready var _acre_host: Node3D = $Acre
@onready var _well_host: Node3D = $WishingWell


func _ready() -> void:
	Clock.paused = true
	Game.reset_session()
	FieldCatalog.set_grass_pattern(WorldData.GrassPattern.TRIANGLE)
	get_viewport().size = Vector2i(960, 540)
	get_tree().root.size = Vector2i(960, 540)
	call_deferred("_run")


func _run() -> void:
	if FieldCatalog.mesh_paths(ACRE_ID).is_empty() or FieldCatalog.mesh_paths(WELL_ID).is_empty():
		push_error("Missing wishing well assets — run tools/build_assets.py first")
		get_tree().quit(1)
		return
	if GeneratedVisual.attach(_acre_host, ACRE_ID) == null:
		push_error("Failed to attach acre %s" % ACRE_ID)
		get_tree().quit(1)
		return
	if GeneratedVisual.attach(_well_host, WELL_ID) == null:
		push_error("Failed to attach well %s" % WELL_ID)
		get_tree().quit(1)
		return

	var acre_half: float = FieldCatalog.ACRE_METERS * 0.5
	_well_host.position = Vector3(acre_half, 0.0, acre_half * 0.82)
	var focus: Vector3 = _well_host.global_position + Vector3(0.0, 2.4, 0.0)
	_camera.current = true

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	print("=== WISHING WELL CAPTURE ===")
	for season: Dictionary in SEASONS:
		Clock.apply_snapshot({
			"year": 2001,
			"month": season["month"],
			"day": season["day"],
			"hour": 12,
			"minute": 0,
		})
		GeneratedVisual.refresh(_acre_host, ACRE_ID)
		GeneratedVisual.refresh(_well_host, WELL_ID)
		await get_tree().process_frame
		await get_tree().process_frame
		var label: String = String(season["name"])
		print("season=", label, " letter=", FieldCatalog.season_letter())
		for shot: Dictionary in _camera_shots(focus):
			_camera.position = shot["pos"]
			_camera.look_at(shot["look"])
			var path := "%s/%s_%s.png" % [OUT_DIR, label, shot["name"]]
			await _save(path)
			print("  wrote ", path)
		_camera.position = focus + Vector3(0.8, 1.1, 2.2)
		_camera.look_at(focus + Vector3(0.0, 1.6, 0.0))
		await _save("%s/%s_canopy_close.png" % [OUT_DIR, label])

	print("shots in ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()


func _camera_shots(focus: Vector3) -> Array[Dictionary]:
	return [
		{
			"name": "front",
			"pos": focus + Vector3(0.0, 1.4, 5.6),
			"look": focus + Vector3(0.0, 1.2, 0.0),
		},
		{
			"name": "three_quarter",
			"pos": focus + Vector3(4.8, 2.0, 4.2),
			"look": focus + Vector3(0.0, 1.3, 0.0),
		},
		{
			"name": "top_down",
			"pos": focus + Vector3(0.2, 7.5, 0.4),
			"look": focus,
		},
	]


func _save(path: String) -> void:
	for _i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var tex := get_viewport().get_texture()
	if tex == null:
		push_error("No viewport texture for %s" % path)
		return
	var img := tex.get_image()
	if img == null:
		push_error("No image for %s" % path)
		return
	var err := img.save_png(path)
	if err != OK:
		push_error("save_png failed (%s): %s" % [err, path])
