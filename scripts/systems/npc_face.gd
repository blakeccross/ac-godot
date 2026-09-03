class_name NpcFace
extends RefCounted

## Drives an `NpcFaceAnim` onto a pipeline character GLB by swapping the eye and mouth
## quads' albedo. `texbank` bakes frame 0 of each into the mesh, so the head already looks
## right; the extra frames come from `--kind faces` when `face_{species}.bin` is available.
##
## Villager model DLs load `anime_1_txt` / `anime_2_txt` with `GX_MIRROR` on S
## (`xct_1.c` / `kab_1.c`): one 32×16 half is mirrored across the bilateral face quad.
## Pipeline GLBs bake that as 64×16; REL exports are 32×16 and must be expanded before swap.

const FRAME_DIR := "res://assets/generated/characters/faces"
## `face_*.bin` eye/mouth blocks are 32x16 CI4. Pipeline GLBs bake the same quads at 64x16.
const FRAME_SIZE := Vector2i(32, 16)
const GLB_FACE_SIZE := Vector2i(64, 16)

var _anim: NpcFaceAnim = NpcFaceAnim.new()
var _eye_mats: Array[StandardMaterial3D] = []
var _mouth_mats: Array[StandardMaterial3D] = []
var _eye_frames: Array[Texture2D] = []
var _mouth_frames: Array[Texture2D] = []
var _eye_shown: int = -1
var _mouth_shown: int = -1
var _target_size := Vector2i.ZERO


static func frame_path(species: StringName, part: String, index: int) -> String:
	return "%s/%s_%s%d.png" % [FRAME_DIR, species, part, index]


static func has_frames(species: StringName) -> bool:
	return ResourceLoader.exists(frame_path(species, "eye", 0))


## Returns true when both quads were found and frames are available to swap.
func bind(visual: Node3D, species: StringName) -> bool:
	_eye_mats.clear()
	_mouth_mats.clear()
	_eye_frames.clear()
	_mouth_frames.clear()
	_target_size = Vector2i.ZERO
	if visual == null:
		return false
	_collect_face_quads(visual)
	if _eye_mats.is_empty() or _mouth_mats.is_empty():
		return false
	_target_size = _quad_size(_eye_mats[0].albedo_texture)
	var use_bin_frames: bool = species == &"boy"
	if use_bin_frames:
		_eye_frames = _load_frames(species, "eye", NpcFaceAnim.EYE_SHUT + 6)
		_mouth_frames = _load_frames(species, "mouth", NpcFaceAnim.MOUTH_OPEN + 4)
	else:
		_eye_frames = _prepare_villager_frames(species, "eye", NpcFaceAnim.EYE_SHUT + 6)
		_mouth_frames = _prepare_villager_frames(species, "mouth", NpcFaceAnim.MOUTH_OPEN + 4)
	if _eye_frames.is_empty():
		_eye_frames = _synthesize_eye_frames(_eye_mats[0].albedo_texture)
	if _mouth_frames.is_empty():
		_mouth_frames = _synthesize_mouth_frames(_mouth_mats[0].albedo_texture)
	if _eye_frames.is_empty() or _mouth_frames.is_empty():
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


## Swap to an emotion pose / blink family. Uses `{species}_eye3..7` / `_mouth3..5`
## when those frames exist; synthesized faces stretch the open frame instead.
## `mouth_hold_override` keeps smile/shock manpu mouths open (`smile1` / `gaaan1` seqs).
func set_emote(emote: NpcFaceAnim.Emote, mouth_hold_override: int = -1) -> void:
	_anim.set_emote(emote, mouth_hold_override)
	_apply()


func set_from_mood(mood: int) -> void:
	set_emote(NpcFaceAnim.emote_from_mood(mood))


func current_emote() -> NpcFaceAnim.Emote:
	return _anim.emote


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


func _collect_face_quads(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			for i: int in mesh_instance.mesh.get_surface_count():
				_try_collect_face_quad(mesh_instance, i)
	for child: Node in node.get_children():
		_collect_face_quads(child)


func _try_collect_face_quad(mesh_instance: MeshInstance3D, surface: int) -> void:
	var mat: Material = mesh_instance.get_active_material(surface)
	if not (mat is StandardMaterial3D):
		return
	var std := mat as StandardMaterial3D
	var tex: Texture2D = std.albedo_texture
	if tex == null or not _is_face_quad(tex):
		return
	var label := _surface_label(mesh_instance, surface)
	var is_eye := "seg_08" in label or ("eye" in label and "seg_09" not in label)
	var is_mouth := "seg_09" in label or "mouth" in label
	if not is_eye and not is_mouth:
		return
	var own := std.duplicate() as StandardMaterial3D
	mesh_instance.set_surface_override_material(surface, own)
	if is_mouth:
		_mouth_mats.append(own)
	else:
		_eye_mats.append(own)


func _prepare_villager_frames(species: StringName, part: String, count: int) -> Array[Texture2D]:
	var raw: Array[Texture2D] = _load_frames(species, part, count)
	if raw.is_empty():
		return raw
	var out: Array[Texture2D] = []
	for tex: Texture2D in raw:
		out.append(_mirror_expand_to(tex, _target_size))
	return out


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


func _surface_label(mesh_instance: MeshInstance3D, surface: int) -> String:
	var bits: PackedStringArray = PackedStringArray()
	bits.append(String(mesh_instance.name).to_lower())
	if mesh_instance.mesh is ArrayMesh:
		bits.append((mesh_instance.mesh as ArrayMesh).surface_get_name(surface).to_lower())
	var mat: Material = mesh_instance.get_active_material(surface)
	if mat != null:
		bits.append(String(mat.resource_name).to_lower())
	return " ".join(bits)


func _synthesize_eye_frames(base: Texture2D) -> Array[Texture2D]:
	var frames: Array[Texture2D] = []
	if base == null:
		return frames
	frames.append(base)
	frames.append(_tint_texture(base, 0.55))
	frames.append(_tint_texture(base, 0.12))
	while frames.size() < 8:
		frames.append(frames[frames.size() - 1])
	return frames


func _synthesize_mouth_frames(base: Texture2D) -> Array[Texture2D]:
	var frames: Array[Texture2D] = []
	if base == null:
		return frames
	frames.append(base)
	frames.append(_tint_texture(base, 1.12))
	frames.append(_tint_texture(base, 1.28))
	while frames.size() < 6:
		frames.append(frames[0])
	return frames


func _tint_texture(tex: Texture2D, factor: float) -> Texture2D:
	var image: Image = _frame_image(tex)
	if image == null:
		return tex
	image = image.duplicate()
	for y: int in image.get_height():
		for x: int in image.get_width():
			var c: Color = image.get_pixel(x, y)
			if c.a <= 0.01:
				continue
			c.r = clampf(c.r * factor, 0.0, 1.0)
			c.g = clampf(c.g * factor, 0.0, 1.0)
			c.b = clampf(c.b * factor, 0.0, 1.0)
			image.set_pixel(x, y, c)
	return ImageTexture.create_from_image(image)


func _mirror_expand_to(tex: Texture2D, target: Vector2i) -> Texture2D:
	if tex == null or target == Vector2i.ZERO:
		return tex
	var image: Image = _frame_image(tex)
	if image == null:
		return tex
	var src := Vector2i(image.get_width(), image.get_height())
	if src == target:
		return tex
	## Authored half (32×16 or ACHD 2:1) → bilateral quad (`GX_MIRROR` on S).
	## Stretching the half across a 4:1 bake is what made Rover's face one-sided.
	if _is_half_face_size(src) and _is_mirrored_face_size(target):
		var half := image
		if src != FRAME_SIZE:
			half = image.duplicate()
			half.resize(FRAME_SIZE.x, FRAME_SIZE.y, Image.INTERPOLATE_NEAREST)
		var mirrored: Image = _mirror_expand_image(half, GLB_FACE_SIZE.x)
		if mirrored.get_width() != target.x or mirrored.get_height() != target.y:
			mirrored.resize(target.x, target.y, Image.INTERPOLATE_NEAREST)
		return ImageTexture.create_from_image(mirrored)
	## Already bilateral (64×16) → ACHD / upscale only.
	if src == GLB_FACE_SIZE and _is_mirrored_face_size(target):
		var copy := image.duplicate()
		copy.resize(target.x, target.y, Image.INTERPOLATE_NEAREST)
		return ImageTexture.create_from_image(copy)
	if target == GLB_FACE_SIZE and src == FRAME_SIZE:
		return ImageTexture.create_from_image(_mirror_expand_image(image, target.x))
	var plain := image.duplicate()
	plain.resize(target.x, target.y, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(plain)


static func _mirror_expand_image(image: Image, target_w: int) -> Image:
	## `GX_MIRROR` on S: copy the authored half across the bilateral face quad.
	var h: int = image.get_height()
	var src_w: int = image.get_width()
	var out := Image.create(target_w, h, false, Image.FORMAT_RGBA8)
	var half_w: int = mini(src_w, target_w / 2)
	for y: int in h:
		for x: int in half_w:
			var c: Color = image.get_pixel(x, y)
			out.set_pixel(x, y, c)
			out.set_pixel(target_w - 1 - x, y, c)
	return out


static func _quad_size(tex: Texture2D) -> Vector2i:
	if tex == null:
		return Vector2i.ZERO
	var sz := tex.get_size()
	return Vector2i(int(sz.x), int(sz.y))


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


static func _is_half_face_size(sz: Vector2i) -> bool:
	## 32×16 authored eye/mouth, or an ACHD upscale of that half (aspect 2:1).
	return (
		sz.y > 0
		and sz.x * FRAME_SIZE.y == sz.y * FRAME_SIZE.x
		and sz.x >= FRAME_SIZE.x
		and sz.x % FRAME_SIZE.x == 0
	)


static func _is_mirrored_face_size(sz: Vector2i) -> bool:
	## 64×16 GX_MIRROR bake, or ACHD of that (aspect 4:1).
	return (
		sz.y > 0
		and sz.x * GLB_FACE_SIZE.y == sz.y * GLB_FACE_SIZE.x
		and sz.x >= GLB_FACE_SIZE.x
		and sz.x % GLB_FACE_SIZE.x == 0
	)


static func _is_face_quad(tex: Texture2D) -> bool:
	## Pipeline may ship native CI4 (32×16), GX_MIRROR bake (64×16), or ACHD
	## upscales of either (e.g. 256×128 half / 512×128 mirrored).
	var sz := tex.get_size()
	var w: int = int(sz.x)
	var h: int = int(sz.y)
	if w <= 0 or h <= 0:
		return false
	return _is_half_face_size(Vector2i(w, h)) or _is_mirrored_face_size(Vector2i(w, h))
