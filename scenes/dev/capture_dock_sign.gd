extends Node3D

## Renders the dock bulletin (`DOCK_SIGN`) on the wharf acre for visual audit.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . --import
##   /Applications/Godot.app/Contents/MacOS/Godot --path . res://scenes/dev/capture_dock_sign.tscn
##
## Output: `res://recordings/dock_sign/*.png`

const OUT_DIR := "res://recordings/dock_sign"

const WHARF_ACRE := &"grd_s_m_wf_1"
const SIGN_ID := &"DOCK_SIGN"
const PORT_SIGN_UT := Vector2i(8, 7)

@onready var _camera: Camera3D = $Camera3D
@onready var _cliff_host: Node3D = $CliffAcre
@onready var _ocean_host: Node3D = $OceanAcre
@onready var _sign_host: Node3D = $Sign


func _ready() -> void:
	Clock.paused = true
	Game.reset_session()
	FieldCatalog.set_grass_pattern(WorldData.GrassPattern.TRIANGLE)
	get_viewport().size = Vector2i(960, 540)
	get_tree().root.size = Vector2i(960, 540)
	call_deferred("_run")


func _run() -> void:
	var ocean_id: StringName = FieldCatalog.ocean_visual_for_beach(WHARF_ACRE)
	if (
		FieldCatalog.mesh_paths(WHARF_ACRE).is_empty()
		or FieldCatalog.mesh_paths(SIGN_ID).is_empty()
	):
		push_error("Missing dock sign assets — run tools/build_assets.py first")
		get_tree().quit(1)
		return
	if GeneratedVisual.attach(_cliff_host, WHARF_ACRE) == null:
		push_error("Failed to attach wharf acre %s" % WHARF_ACRE)
		get_tree().quit(1)
		return
	if ocean_id != &"" and not FieldCatalog.mesh_paths(ocean_id).is_empty():
		_ocean_host.position.z = -FieldCatalog.ACRE_METERS
		if GeneratedVisual.attach(_ocean_host, ocean_id) == null:
			push_warning("Failed to attach ocean acre %s" % ocean_id)
	if GeneratedVisual.attach(_sign_host, SIGN_ID) == null:
		push_error("Failed to attach sign %s" % SIGN_ID)
		get_tree().quit(1)
		return

	var unit_m: float = FieldCatalog.ACRE_METERS / float(WorldGenerator.UT)
	## `PORT_SIGN` FG unit on `grd_s_m_wf_*` (see `FgCatalog.ITEM_PORT_SIGN`).
	_sign_host.position = Vector3(
		(PORT_SIGN_UT.x + 0.5) * unit_m,
		0.0,
		(PORT_SIGN_UT.y + 0.5) * unit_m,
	)
	var focus: Vector3 = _sign_host.global_position + Vector3(0.0, 1.4, 0.0)
	_camera.current = true

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	print("=== DOCK SIGN CAPTURE ===")
	await get_tree().process_frame
	await get_tree().process_frame

	for shot: Dictionary in _camera_shots(focus):
		_camera.position = shot["pos"]
		_camera.look_at(shot["look"])
		var path := "%s/%s.png" % [OUT_DIR, shot["name"]]
		await _save(path)
		print("  wrote ", path)

	print("shots in ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()


func _camera_shots(focus: Vector3) -> Array[Dictionary]:
	return [
		{
			"name": "ocean_cliff",
			"pos": focus + Vector3(3.2, 2.2, 4.8),
			"look": focus + Vector3(0.0, 0.6, 0.0),
		},
		{
			"name": "ocean_top_down",
			"pos": focus + Vector3(0.6, 6.0, 3.0),
			"look": focus + Vector3(0.0, 0.2, -1.0),
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
