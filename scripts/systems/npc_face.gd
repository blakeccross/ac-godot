class_name NpcFace
extends RefCounted

## Drives an `NpcFaceAnim` onto a pipeline character GLB by swapping the eye and mouth
## quads' albedo. `texbank` bakes frame 0 of each into the mesh, so the head already looks
## right; the extra frames come from `--kind faces`.
##
## The GLB embeds its textures without names, so the eye and mouth surfaces are found by
## matching a surface's albedo against the frame-0 PNGs. Both come from the same decode of
## the same `face_*.bin` block, so the pixels are identical, and this needs no assumption
## about display-list or material naming.

const FRAME_DIR := "res://assets/generated/characters/faces"
## `face_*.bin` eye/mouth blocks are 32x16 CI4.
const FRAME_SIZE := Vector2i(32, 16)

var _anim: NpcFaceAnim = NpcFaceAnim.new()
var _eye_mats: Array[StandardMaterial3D] = []
var _mouth_mats: Array[StandardMaterial3D] = []
var _eye_frames: Array[Texture2D] = []
var _mouth_frames: Array[Texture2D] = []
var _eye_shown: int = -1
var _mouth_shown: int = -1


static func frame_path(species: StringName, part: String, index: int) -> String:
	return "%s/%s_%s%d.png" % [FRAME_DIR, species, part, index]


static func has_frames(species: StringName) -> bool:
	return ResourceLoader.exists(frame_path(species, "eye", 0))


## Returns true when both quads were found and there is more than one frame to show.
func bind(visual: Node3D, species: StringName) -> bool:
	_eye_mats.clear()
	_mouth_mats.clear()
	_eye_frames = _load_frames(species, "eye", NpcFaceAnim.EYE_SHUT + 6)
	_mouth_frames = _load_frames(species, "mouth", NpcFaceAnim.MOUTH_OPEN + 4)
	if visual == null or _eye_frames.is_empty() or _mouth_frames.is_empty():
		return false
	var eye_ref: Image = _frame_image(_eye_frames[0])
	var mouth_ref: Image = _frame_image(_mouth_frames[0])
	if eye_ref == null or mouth_ref == null:
		return false
	_collect(visual, eye_ref, mouth_ref)
	if _eye_mats.is_empty() and _mouth_mats.is_empty():
		return false
	_eye_shown = -1
	_mouth_shown = -1
	_apply()
	return true


func tick(delta: float, uttering: bool) -> void:
	if _eye_mats.is_empty() and _mouth_mats.is_empty():
		return
	if _anim.tick(delta, uttering):
		_apply()


func _apply() -> void:
	var eye: int = _anim.eye_pattern
	if eye != _eye_shown and eye < _eye_frames.size():
		_eye_shown = eye
		for mat: StandardMaterial3D in _eye_mats:
			mat.albedo_texture = _eye_frames[eye]
	var mouth: int = _anim.mouth_pattern
	if mouth != _mouth_shown and mouth < _mouth_frames.size():
		_mouth_shown = mouth
		for mat: StandardMaterial3D in _mouth_mats:
			mat.albedo_texture = _mouth_frames[mouth]


func _load_frames(species: StringName, part: String, count: int) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for i: int in count:
		var path := frame_path(species, part, i)
		if not ResourceLoader.exists(path):
			break
		var tex: Texture2D = load(path) as Texture2D
		if tex == null:
			break
		out.append(tex)
	return out


func _collect(node: Node, eye_ref: Image, mouth_ref: Image) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			for i: int in mesh_instance.mesh.get_surface_count():
				_classify(mesh_instance, i, eye_ref, mouth_ref)
	for child: Node in node.get_children():
		_collect(child, eye_ref, mouth_ref)


func _classify(
	mesh_instance: MeshInstance3D, surface: int, eye_ref: Image, mouth_ref: Image
) -> void:
	var mat: Material = mesh_instance.get_active_material(surface)
	if not (mat is StandardMaterial3D):
		return
	var std := mat as StandardMaterial3D
	var tex: Texture2D = std.albedo_texture
	if tex == null or tex.get_size() != Vector2(FRAME_SIZE):
		return
	var image: Image = _frame_image(tex)
	if image == null:
		return
	var is_eye := _same_pixels(image, eye_ref)
	var is_mouth := _same_pixels(image, mouth_ref)
	if not is_eye and not is_mouth:
		return
	## Swapping needs a material this face owns; the imported one is shared per texture.
	var own := std.duplicate() as StandardMaterial3D
	mesh_instance.set_surface_override_material(surface, own)
	if is_eye:
		_eye_mats.append(own)
	else:
		_mouth_mats.append(own)


func _frame_image(tex: Texture2D) -> Image:
	if tex == null:
		return null
	var image: Image = tex.get_image()
	if image == null:
		return null
	if image.is_compressed():
		image = image.duplicate()
		if image.decompress() != OK:
			return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image = image.duplicate()
		image.convert(Image.FORMAT_RGBA8)
	return image


static func _same_pixels(a: Image, b: Image) -> bool:
	if a == null or b == null or a.get_size() != b.get_size():
		return false
	return a.get_data() == b.get_data()
