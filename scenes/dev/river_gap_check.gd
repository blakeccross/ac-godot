extends Node3D

## Renders a single generated field acre (default: the c5_r2 river-bend corner) through
## the real `GeneratedVisual.attach` path, for visually diagnosing the right-edge water
## gap reported against `grd_s_c5_r2`. Pass `--acre=<visual_id>` to check a different one.

@onready var _camera: Camera3D = $Camera3D
@onready var _status: Label = $CanvasLayer/Status

var _shot_frames: int = 0
var _wants_screenshot: bool = false


func _ready() -> void:
	_wants_screenshot = "--screenshot" in OS.get_cmdline_user_args()
	var visual_id := StringName(_arg("acre", "grd_s_c5_r2_1"))
	var host := Node3D.new()
	$Anchor.add_child(host)
	var pivot: Node3D = GeneratedVisual.attach(host, visual_id)
	if pivot == null:
		_status.text = "GeneratedVisual.attach failed for %s" % visual_id
		return
	## Optional second acre placed edge-to-edge along +X, using this acre's own
	## post-fit AABB width as the neighbor offset — reproduces `world_builder.gd`'s
	## zero-overlap grid placement (`grid.cell_corner`) for a two-acre seam check.
	var neighbor_id := StringName(_arg("neighbor", ""))
	if neighbor_id != &"":
		var width: float = _mesh_aabb(host).size.x
		var host2 := Node3D.new()
		$Anchor.add_child(host2)
		host2.position = Vector3(width, 0.0, 0.0)
		GeneratedVisual.attach(host2, neighbor_id)
	_frame_camera($Anchor)
	_status.text = String(visual_id) + (" + " + String(neighbor_id) if neighbor_id != &"" else "")


func _arg(key: String, default: String) -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.substr(key.length() + 3)
	return default


func _process(_delta: float) -> void:
	if not _wants_screenshot:
		return
	_shot_frames += 1
	if _shot_frames < 12:
		return
	_wants_screenshot = false
	var tex := get_viewport().get_texture()
	var image: Image = tex.get_image() if tex != null else null
	if image == null:
		push_error("No viewport image (headless renderer cannot screenshot)")
		get_tree().quit()
		return
	var out_path := OS.get_user_data_dir().path_join("river_gap_check.png")
	image.save_png(out_path)
	print("Wrote screenshot ", out_path)
	get_tree().quit()


func _frame_camera(root: Node) -> void:
	var aabb := _mesh_aabb(root)
	if aabb.size == Vector3.ZERO:
		return
	var center := aabb.get_center()
	var radius: float = aabb.size.length() * 0.7
	_camera.look_at_from_position(center + Vector3(radius * 0.15, radius * 0.9, radius * 0.05), center, Vector3.UP)


func _mesh_aabb(node: Node) -> AABB:
	var merged := AABB()
	var started := false
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			merged = mi.global_transform * mi.mesh.get_aabb()
			started = true
	for child in node.get_children():
		var child_aabb := _mesh_aabb(child)
		if child_aabb.size != Vector3.ZERO:
			if started:
				merged = merged.merge(child_aabb)
			else:
				merged = child_aabb
				started = true
	return merged
