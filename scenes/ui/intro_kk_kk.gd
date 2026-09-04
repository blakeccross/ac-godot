class_name IntroKkAnim
extends Node3D

## K.K. Slider host for the player-select opening (`SP_NPC_P_SEL` / `end_1`).

const ANIM_STRUM := IntroKkStage.ANIM_STRUM
const ANIM_LOOK_UP := IntroKkStage.ANIM_LOOK_UP
const GUITAR_ATTACH := "KkGuitar"
## Chest — furniture guitar sits across the torso (`4haku` / ensou). Not a hand TOOL.
const GUITAR_BONE := "chest_end_model"

var _anim: AnimationPlayer
var _tree: AnimationTree
var _active: String = ""
var _face: NpcFace = NpcFace.new()


func _ready() -> void:
	global_position = IntroKkStage.gx_to_meters(IntroKkStage.KK_SPAWN_GX)
	rotation = Vector3(0.0, IntroKkStage.KK_YAW, 0.0)
	_ensure_visual()
	_setup_player()
	_bind_face()
	_attach_guitar()
	## Play now and again next frame — GLB AnimationPlayer finishes ready one tick later.
	play_strum()
	call_deferred("play_strum")
	call_deferred("_snap_posed_to_floor")


func body_animation_player() -> AnimationPlayer:
	return _anim


func tick_face(delta: float, uttering: bool) -> void:
	_face.tick(delta, uttering)


func play_strum() -> bool:
	return _play(ANIM_STRUM, true, IntroKkStage.STRUM_SPEED, IntroKkStage.MORPH_STRUM)


func play_look_up() -> bool:
	return _play(ANIM_LOOK_UP, true, 1.0, IntroKkStage.MORPH_LOOK_UP)


func apply_pose(pose: int) -> bool:
	match pose:
		IntroKkStage.Pose.LOOK_UP:
			return play_look_up()
		_:
			return play_strum()


func _bind_face() -> void:
	var vis: Node3D = get_node_or_null("GeneratedVisual") as Node3D
	if vis == null:
		return
	if _face.bind(vis, IntroKkStage.FACE_SPECIES):
		_face.set_emote(NpcFaceAnim.Emote.NORMAL)


func _ensure_visual() -> void:
	var vis: Node3D = get_node_or_null("GeneratedVisual") as Node3D
	if vis == null:
		return
	GeneratedVisual.apply_actor_scale(vis)
	## Rest AABB then posed snap — `4haku` sits; rest feet alone leave him floating/clipped.
	GeneratedVisual.align_actor_to_height_gx(vis, 0.0)
	GeneratedVisual.apply_preview_materials(vis)
	## ACHD ear fringe can flip a surface to BLEND; keep the body fully opaque.
	_force_opaque_materials(vis)
	GeneratedVisual.stop_autoplay(vis)


func _force_opaque_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var count: int = mesh_instance.mesh.get_surface_count() if mesh_instance.mesh != null else 0
		for i: int in count:
			var mat: Material = mesh_instance.get_active_material(i)
			if mat == null:
				continue
			var std: StandardMaterial3D
			if mat is StandardMaterial3D:
				std = (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			else:
				continue
			std.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			std.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_OFF
			mesh_instance.set_surface_override_material(i, std)
	for child in node.get_children():
		_force_opaque_materials(child)


func _snap_posed_to_floor() -> void:
	var vis: Node3D = get_node_or_null("GeneratedVisual") as Node3D
	if vis != null:
		GeneratedVisual.align_actor_world_min_to_height_gx(vis, 0.0)


func _setup_player() -> void:
	_anim = GeneratedVisual.find_animation_player(self)
	_tree = get_node_or_null("AnimationTree") as AnimationTree
	if _tree != null:
		_tree.active = false


func _guitar_local() -> Transform3D:
	## Furniture GLB is room-prop sized; scale for chest prop.
	const PROP_SCALE := 0.28
	var basis := Basis.from_euler(
		Vector3(deg_to_rad(-5.0), deg_to_rad(95.0), deg_to_rad(8.0))
	).scaled(Vector3.ONE * PROP_SCALE)
	return Transform3D(basis, Vector3(0.0, -0.08, 0.45))


func _attach_guitar() -> void:
	if not ResourceLoader.exists(IntroKkStage.GUITAR_PATH):
		return
	var skeleton: Skeleton3D = HeldTool.find_skeleton(self)
	if skeleton == null:
		return
	var bone := GUITAR_BONE
	if skeleton.find_bone(bone) == -1:
		bone = "joint_20" if skeleton.find_bone("joint_20") != -1 else ""
	if bone.is_empty():
		return
	## Immediate free — `queue_free` leaves the old attach alive same-frame and
	## Godot renames the new one to `KkGuitar2` (stacked props).
	var existing: Node = skeleton.get_node_or_null(GUITAR_ATTACH)
	if existing != null:
		skeleton.remove_child(existing)
		existing.free()
	var packed: PackedScene = load(IntroKkStage.GUITAR_PATH) as PackedScene
	if packed == null:
		return
	var guitar: Node3D = packed.instantiate() as Node3D
	if guitar == null:
		return
	var attach := BoneAttachment3D.new()
	attach.name = GUITAR_ATTACH
	skeleton.add_child(attach)
	attach.bone_name = bone
	attach.add_child(guitar)
	guitar.transform = _guitar_local()
	## Drop stand cradles only — keep the 3D body (front/back/side/neck).
	## A front-only card over the black void reads as a black box around the cutout.
	_strip_guitar_extra_surfaces(guitar)
	_apply_guitar_cutout_material(guitar)


func _apply_guitar_cutout_material(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var mesh: Mesh = mesh_instance.mesh
		var count: int = mesh.get_surface_count() if mesh != null else 0
		for i: int in count:
			var mat: Material = mesh_instance.get_active_material(i)
			if mat == null and mesh != null:
				mat = mesh.surface_get_material(i)
			if not mat is StandardMaterial3D:
				continue
			var std := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			std.cull_mode = BaseMaterial3D.CULL_BACK
			std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			std.alpha_scissor_threshold = 0.5
			std.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_OFF
			std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
			std.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			std.roughness = 1.0
			std.metallic = 0.0
			mesh_instance.set_surface_override_material(i, std)
	for child in node.get_children():
		_apply_guitar_cutout_material(child)


func _strip_guitar_extra_surfaces(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var mesh: Mesh = mesh_instance.mesh
		if mesh is ArrayMesh:
			var src := mesh as ArrayMesh
			var kept := ArrayMesh.new()
			for i: int in src.get_surface_count():
				var surf_name := src.surface_get_name(i).to_lower()
				## Stand cradles only — keep front/back/side/neck for a solid body.
				## Omitting `back` leaves a black void hole through the shell.
				if surf_name.ends_with("_chest") or surf_name.ends_with("_hand"):
					continue
				kept.add_surface_from_arrays(src.surface_get_primitive_type(i), src.surface_get_arrays(i))
				var new_i: int = kept.get_surface_count() - 1
				kept.surface_set_name(new_i, src.surface_get_name(i))
				var mat: Material = src.surface_get_material(i)
				if mat != null:
					kept.surface_set_material(new_i, mat)
			mesh_instance.mesh = kept
	for child in node.get_children():
		_strip_guitar_extra_surfaces(child)


func _play(suffix: String, loop: bool, speed: float, blend: float = 0.0) -> bool:
	if _anim == null:
		_setup_player()
	if _anim == null:
		return false
	var clip: String = IntroKkStage.resolve_clip(_anim, suffix)
	if clip.is_empty():
		return false
	if _tree != null:
		_tree.active = false
	if _active == clip and _anim.is_playing():
		_anim.speed_scale = speed
		return true
	var anim: Animation = _anim.get_animation(clip)
	if anim != null:
		anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	_active = clip
	_anim.speed_scale = speed
	_anim.play(clip, blend)
	return true
