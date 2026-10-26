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
## Each face set's palette and the sunburn palettes (`mPlib_Get_UseFacePalletRom_p`), written by
## the pipeline from `face_boy.bin`.
const PALETTES := FACE_DIR + "palettes.json"
## The body textures drawn with the face palette (segment 0x0C) were baked with set 0's.
const BAKED_SET := 0

static var _palettes: Dictionary = {}
static var _tanned: Dictionary = {}


## `mPlib_Get_UseFaceRom_index` (TEX): decoy·32 + face + sex·8 + swell·16.
static func set_index(female: bool, face: int, swell: bool) -> int:
	return clampi(face, 0, SEX_OFFSET - 1) + (SEX_OFFSET if female else 0) + (SWELL_OFFSET if swell else 0)


static func eye_path(set_idx: int, eye: int = 0) -> String:
	return FACE_DIR + "face_%02d_%02d.png" % [set_idx, clampi(eye, 0, EYE_TEX_NUM - 1)]


static func mouth_path(set_idx: int, mouth: int = 0) -> String:
	return FACE_DIR + "face_%02d_%02d.png" % [set_idx, EYE_TEX_NUM + clampi(mouth, 0, MOUTH_TEX_NUM - 1)]


## `mPlib_Get_UseFaceRom_index` (PAL): the sunburn palette for a rank.
static func tan_index(female: bool, face: int, swell: bool, rank: int) -> int:
	return rank + clampi(face, 0, SEX_OFFSET - 1) * 8 + (64 if female else 0) + (128 if swell else 0)


## Paint the current face onto every eye / mouth surface under `host`; a sunburn `tan`
## rank (1–8) swaps the face palette, which also colours the skin.
static func apply(host: Node, female: bool, face: int, swell: bool, tan: int = 0) -> void:
	var idx: int = set_index(female, face, swell)
	var eye: Texture2D = _load(eye_path(idx))
	var mouth: Texture2D = _load(mouth_path(idx))
	if eye == null and mouth == null:
		return
	var to: Array = _tan_palette(tan_index(female, face, swell, tan)) if tan > 0 else []
	if not to.is_empty():
		var own: Array = _set_palette(idx)
		eye = _recolor(eye, own, to)
		mouth = _recolor(mouth, own, to)
	_paint(host, eye, mouth)
	_paint_skin(host, _set_palette(BAKED_SET), to)


static func _ensure_palettes() -> void:
	if not _palettes.is_empty() or not FileAccess.file_exists(PALETTES):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PALETTES))
	if typeof(parsed) == TYPE_DICTIONARY:
		_palettes = parsed


static func _set_palette(idx: int) -> Array:
	_ensure_palettes()
	var sets: Array = _palettes.get("sets", [])
	return sets[idx] if idx >= 0 and idx < sets.size() else []


static func _tan_palette(idx: int) -> Array:
	_ensure_palettes()
	var tan: Array = _palettes.get("tan", [])
	return tan[idx] if idx >= 0 and idx < tan.size() else []


## Index-for-index colour swap of a CI4 texture decoded with palette `from`.
static func _recolor(tex: Texture2D, from: Array, to: Array) -> Texture2D:
	if tex == null or from.size() != to.size() or from.is_empty():
		return tex
	var key: String = "%s|%s" % [tex.resource_path if tex.resource_path != "" else str(tex.get_rid()), str(to)]
	if _tanned.has(key):
		return _tanned[key]
	var img: Image = tex.get_image()
	if img == null:
		return tex
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var swap: Dictionary = {}
	for i: int in from.size():
		var a := Color.html(str(from[i]))
		var b := Color.html(str(to[i]))
		swap[a.to_rgba32() | 0xFF] = b
	for y: int in img.get_height():
		for x: int in img.get_width():
			var c: Color = img.get_pixel(x, y)
			var k: int = Color(c.r, c.g, c.b, 1.0).to_rgba32()
			if swap.has(k):
				var n: Color = swap[k]
				img.set_pixel(x, y, Color(n.r, n.g, n.b, c.a))
	var out := ImageTexture.create_from_image(img)
	_tanned[key] = out
	return out


## The model's own `*_tex_txt` surfaces drawn with the face palette: tanned, or back to the
## mesh's material when `to` is empty.
static func _paint_skin(node: Node, from: Array, to: Array) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var count: int = mi.mesh.get_surface_count() if mi.mesh != null else 0
		for i: int in count:
			var base := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if base == null or base.resource_name.begins_with("seg_") or base.albedo_texture == null:
				continue
			var current: Material = mi.get_surface_override_material(i)
			if to.is_empty():
				if current != null and current.has_meta(&"tan"):
					mi.set_surface_override_material(i, null)
				continue
			if current != null and not current.has_meta(&"tan"):
				continue
			var tex: Texture2D = _recolor(base.albedo_texture, from, to)
			if tex == base.albedo_texture:
				continue
			var std := base.duplicate() as StandardMaterial3D
			std.albedo_texture = tex
			std.set_meta(&"tan", true)
			mi.set_surface_override_material(i, std)
	for child: Node in node.get_children():
		_paint_skin(child, from, to)


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
