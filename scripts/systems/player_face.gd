class_name PlayerFace
extends RefCounted

## The player's eye / mouth textures (`mPlib_Get_UseFaceRom_index`, `mPlib_Get_eye_tex_p`).
## `face_boy.bin` holds 64 sets of 8 eye + 6 mouth 32×16 frames; a set is picked by face type,
## sex and the bee-swell flag (+16), and the model binds the eye to segment 8, the mouth to 9.

const FACE_DIR := "res://assets/generated/textures/player/faces/"
const EYE_TEX_NUM := 8
const MOUTH_TEX_NUM := 6
const SWELL_OFFSET := 16
const SEX_OFFSET := 8
const EYE_SEGMENT := "seg_08"
const MOUTH_SEGMENT := "seg_09"


## `mPlib_Get_UseFaceRom_index` (TEX): decoy·32 + face + sex·8 + swell·16.
static func set_index(female: bool, face: int, swell: bool) -> int:
	return clampi(face, 0, SEX_OFFSET - 1) + (SEX_OFFSET if female else 0) + (SWELL_OFFSET if swell else 0)


static func eye_path(set_idx: int, eye: int = 0) -> String:
	return FACE_DIR + "face_%02d_%02d.png" % [set_idx, clampi(eye, 0, EYE_TEX_NUM - 1)]


static func mouth_path(set_idx: int, mouth: int = 0) -> String:
	return FACE_DIR + "face_%02d_%02d.png" % [set_idx, EYE_TEX_NUM + clampi(mouth, 0, MOUTH_TEX_NUM - 1)]


## Paint the current face onto every eye / mouth surface under `host`.
static func apply(host: Node, female: bool, face: int, swell: bool) -> void:
	var idx: int = set_index(female, face, swell)
	var eye: Texture2D = _load(eye_path(idx))
	var mouth: Texture2D = _load(mouth_path(idx))
	if eye == null and mouth == null:
		return
	_paint(host, eye, mouth)


static func _load(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


static func _paint(node: Node, eye: Texture2D, mouth: Texture2D) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var count: int = mi.mesh.get_surface_count() if mi.mesh != null else 0
		for i: int in count:
			var mat := mi.get_active_material(i) as StandardMaterial3D
			if mat == null:
				continue
			var tex: Texture2D = null
			if mat.resource_name == EYE_SEGMENT:
				tex = eye
			elif mat.resource_name == MOUTH_SEGMENT:
				tex = mouth
			if tex == null or mat.albedo_texture == tex:
				continue
			var std := mat.duplicate() as StandardMaterial3D
			std.albedo_texture = tex
			mi.set_surface_override_material(i, std)
	for child: Node in node.get_children():
		_paint(child, eye, mouth)
