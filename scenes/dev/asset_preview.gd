extends Node3D

## Loads generated pipeline meshes for visual checks. Missing files are expected
## until `python3 tools/build_assets.py` has been run locally.

const PLAYER_PATH := "res://assets/generated/characters/player/boy_1.glb"

@onready var _camera: Camera3D = $Camera3D
@onready var _status: Label = $CanvasLayer/Status

var _shot_frames: int = 0
var _wants_screenshot: bool = false


func _ready() -> void:
	_wants_screenshot = "--screenshot" in OS.get_cmdline_user_args()
	if not ResourceLoader.exists(PLAYER_PATH):
		_status.text = "Run python3 tools/build_assets.py — missing %s" % PLAYER_PATH
		return
	var packed: PackedScene = load(PLAYER_PATH) as PackedScene
	if packed == null:
		_status.text = "Godot could not import %s" % PLAYER_PATH
		return
	var inst: Node = packed.instantiate()
	$Anchor.add_child(inst)
	_apply_vertex_colors(inst)
	_play_idle(inst)
	_frame_camera(inst)
	_status.text = "player_boy_1"


func _process(_delta: float) -> void:
	if not _wants_screenshot:
		return
	_shot_frames += 1
	if _shot_frames < 12:
		return
	_wants_screenshot = false
	var tex := get_viewport().get_texture()
	if tex == null:
		push_error("No viewport texture (headless renderer cannot screenshot)")
		get_tree().quit()
		return
	var image: Image = tex.get_image()
	if image == null:
		push_error("No viewport image (headless renderer cannot screenshot)")
		get_tree().quit()
		return
	var out_path := OS.get_user_data_dir().path_join("asset_preview.png")
	image.save_png(out_path)
	print("Wrote screenshot ", out_path)
	get_tree().quit()


func _play_idle(node: Node) -> void:
	if node is AnimationPlayer:
		var player := node as AnimationPlayer
		for anim_name in player.get_animation_list():
			if "wait" in anim_name:
				player.play(anim_name)
				return
		if player.get_animation_list():
			player.play(player.get_animation_list()[0])
		return
	for child in node.get_children():
		_play_idle(child)


func _apply_vertex_colors(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var mat := mesh_instance.get_active_material(0)
		if mat == null:
			mat = StandardMaterial3D.new()
			mesh_instance.set_surface_override_material(0, mat)
		if mat is StandardMaterial3D:
			var std := mat as StandardMaterial3D
			std.vertex_color_use_as_albedo = false
			std.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			std.cull_mode = BaseMaterial3D.CULL_DISABLED
	for child in node.get_children():
		_apply_vertex_colors(child)


func _frame_camera(root: Node) -> void:
	var aabb := _mesh_aabb(root)
	if aabb.size == Vector3.ZERO:
		return
	var center := aabb.get_center()
	var radius: float = aabb.size.length() * 0.6
	_camera.look_at_from_position(center + Vector3(radius, radius * 0.45, radius), center, Vector3.UP)


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
