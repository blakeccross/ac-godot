extends Node3D

## FG `LOTUS` (`ac_lotus`): a lily-pad cluster floating on a pond. Leaves sway on the baked
## `obj_s_lotus` clip; the flower joint only draws from May 26 through Aug 25.
## Not solid (it floats on water) and has no verb.

@export var visual_id: StringName = &"obj_s_lotus"
@export var occupant_id: StringName = &""
@export var footprint: Vector2i = Vector2i(1, 1)
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = false

## `cKF_SkeletonInfo_R_init(…, 1.0, 129.0, 1.0, 0.5, …, TRUE)`: loops at half speed.
const CLIP_SPEED := 0.5
const FLOWER_MESH := "obj_s_lotus"

## PLACEHOLDER COLOR. The CI4 lotus textures take their palette at draw time from
## `aLOT_obj_0N_lotus_pal` (`paltbl[aLOT_getPalNo()]`), which the pipeline does not bake yet, so the
## GLBs carry a debug palette. Recolor those exact debug colors (RGBA8 → RGBA8) to lily green and
## pink until a per-term palette bake replaces this.
const LEAF_REMAP := {
	0xFFFFFFFF: 0x58A848FF,
	0x83A4FFFF: 0x00000000,
	0xFFEE00FF: 0x70B840FF,
	0xFF0000FF: 0x348034FF,
	0xFF3131FF: 0x348034FF,
	0x0041FFFF: 0x24602CFF,
}
const FLOWER_REMAP := {
	0x183139FF: 0x00000000,
	0x730000FF: 0xC83C78FF,
	0xB40000FF: 0xE65A96FF,
	0xFFB400FF: 0xFA96BEFF,
	0x62DE20FF: 0xFFD7E6FF,
	0x20BD00FF: 0xFFF5FAFF,
}
static var _recolored: Dictionary = {} ## remap dict id → ImageTexture

var _anim: AnimationPlayer


func _ready() -> void:
	_attach()
	if Clock != null and not Clock.day_changed.is_connected(_sync_flower):
		Clock.day_changed.connect(_sync_flower)


func _exit_tree() -> void:
	if Clock != null and Clock.day_changed.is_connected(_sync_flower):
		Clock.day_changed.disconnect(_sync_flower)


func refresh_seasonal_visual() -> void:
	GeneratedVisual.refresh(self, visual_id)
	_attach_done()


func _attach() -> void:
	if GeneratedVisual.attach(self, visual_id) == null:
		return
	_attach_done()


func _attach_done() -> void:
	_anim = VisualAnimation.find_animation_player(self)
	if _anim != null:
		var clip: StringName = _first_clip(_anim)
		if clip != &"":
			_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
			_anim.speed_scale = CLIP_SPEED
			_anim.play(clip)
	_recolor_placeholder()
	_sync_flower()


func _recolor_placeholder() -> void:
	for mi: MeshInstance3D in _mesh_instances(self):
		var remap: Dictionary = FLOWER_REMAP if mi.name == FLOWER_MESH else LEAF_REMAP
		for surface: int in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(surface) as StandardMaterial3D
			if mat == null or mat.albedo_texture == null:
				continue
			var tinted := mat.duplicate() as StandardMaterial3D
			tinted.albedo_texture = _remapped(remap, mat.albedo_texture)
			tinted.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			tinted.alpha_scissor_threshold = 0.5
			mi.set_surface_override_material(surface, tinted)


static func _remapped(remap: Dictionary, source: Texture2D) -> Texture2D:
	var key: int = remap.hash()
	if _recolored.has(key):
		return _recolored[key] as Texture2D
	var img: Image = source.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	for y: int in img.get_height():
		for x: int in img.get_width():
			var rgba: int = img.get_pixel(x, y).to_rgba32()
			if remap.has(rgba):
				img.set_pixel(x, y, Color.hex(int(remap[rgba])))
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	_recolored[key] = tex
	return tex


func _mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		out.append_array(_mesh_instances(child))
	return out


func _sync_flower() -> void:
	var shown: bool = flower_in_bloom(Clock.month if Clock != null else 6, Clock.day if Clock != null else 1)
	var flower: Node = _find_named(self, FLOWER_MESH)
	if flower is MeshInstance3D:
		(flower as MeshInstance3D).visible = shown


## `aLOT_actor_draw_before` joint 0x12: `on_off_tbl` is May–Jul, with the May and Aug day-26 edges.
static func flower_in_bloom(month: int, day: int) -> bool:
	if month == 5:
		return day >= 26
	if month == 8:
		return day < 26
	return month == 6 or month == 7


func _first_clip(anim: AnimationPlayer) -> StringName:
	for clip: StringName in anim.get_animation_list():
		if clip != &"RESET":
			return clip
	return &""


func _find_named(node: Node, want: String) -> Node:
	if node is MeshInstance3D and node.name == want:
		return node
	for child in node.get_children():
		var found: Node = _find_named(child, want)
		if found != null:
			return found
	return null
