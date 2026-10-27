extends Node3D

## Renders the wishing well on its shrine acre and saves PNGs for visual audit.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . res://scenes/dev/capture_wishing_well.tscn
##
## Output: `res://recordings/wishing_well/*.png`

const OUT_DIR := "res://recordings/wishing_well"

const ACRE_ID := &"grd_s_f_pk_2"
const WELL_ID := &"obj_s_shrine"

const SEASONS: Array[Dictionary] = [
	## Dolphin save slot 9: Thursday 3 October, about 9:10pm. First so a stall
	## later still leaves the comparison frames.
	{ "name": "autumn_night", "month": 10, "day": 3, "hour": 21, "minute": 10 },
	{ "name": "summer", "month": 7, "day": 15, "hour": 12, "minute": 0 },
	{ "name": "autumn", "month": 10, "day": 20, "hour": 12, "minute": 0 },
	{ "name": "winter", "month": 1, "day": 15, "hour": 12, "minute": 0 },
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
	OS.low_processor_usage_mode = false
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
	FieldLit.apply_solid(_well_host)

	var acre_half: float = FieldCatalog.ACRE_METERS * 0.5
	_well_host.position = Vector3(acre_half, 0.0, acre_half * 0.82)
	var focus: Vector3 = _well_host.global_position + Vector3(0.0, 2.4, 0.0)
	## Basin center in the shrine mesh (splash ring sits around z = 4).
	var basin: Vector3 = _well_host.global_position + Vector3(0.0, 0.55, 4.0)
	_camera.current = true

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	print("=== WISHING WELL CAPTURE ===")
	for season: Dictionary in SEASONS:
		Clock.apply_snapshot({
			"year": 2001,
			"month": season["month"],
			"day": season["day"],
			"hour": season["hour"],
			"minute": season["minute"],
		})
		_apply_outdoor_light()
		GeneratedVisual.refresh(_acre_host, ACRE_ID)
		GeneratedVisual.refresh(_well_host, WELL_ID)
		FieldLit.apply_solid(_well_host)
		await get_tree().process_frame
		await get_tree().process_frame
		var label: String = String(season["name"])
		print("season=", label, " letter=", FieldCatalog.season_letter())
		for shot: Dictionary in _camera_shots(focus, basin):
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


func _apply_outdoor_light() -> void:
	## Same kankyo row the field uses, so the basin shader's shade matches the stone.
	var pal := Clock.outdoor_light()
	var sun := $Sun as DirectionalLight3D
	var moon := $Fill as DirectionalLight3D
	sun.light_color = pal["sun"]
	sun.light_energy = float(pal["sun_energy"])
	moon.light_color = pal["moon"]
	moon.light_energy = float(pal["moon_energy"])
	var env := ($WorldEnvironment as WorldEnvironment).environment
	env.ambient_light_color = pal["ambient"]
	env.background_color = pal["bg"]
	for pair: Array in [
		[&"field_ambient", pal["ambient"]],
		[&"field_sun_color", pal["sun"]],
		[&"field_moon_color", pal["moon"]],
	]:
		var color: Color = pair[1]
		RenderingServer.global_shader_parameter_set(pair[0], Vector3(color.r, color.g, color.b))
	RenderingServer.global_shader_parameter_set(&"field_sun_dir", pal["sun_dir"])
	RenderingServer.global_shader_parameter_set(&"field_moon_dir", pal["moon_dir"])


func _camera_shots(focus: Vector3, basin: Vector3) -> Array[Dictionary]:
	return [
		{
			"name": "basin",
			"pos": basin + Vector3(0.5, 3.4, 5.0),
			"look": basin + Vector3(0.0, 0.15, -0.8),
		},
		{
			"name": "basin_top",
			"pos": basin + Vector3(0.05, 5.2, 0.12),
			"look": basin,
		},
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
	await get_tree().process_frame
	await get_tree().process_frame
	RenderingServer.force_draw()
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
