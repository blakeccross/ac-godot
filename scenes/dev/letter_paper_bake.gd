extends Node

## One-time bake: render each `lat_letterNN.glb` stationery model flat-on with an
## orthographic camera and save the result as `ui/letter/paperNN.png`.
##
## Why a render instead of grabbing a texture out of the glb directly: each stationery
## model layers several materials (front/back paper, corner accents, wax-seal/ribbon
## decals, alpha-blended overlays) across its mesh, and picking "the" background
## texture by name or pixel size is unreliable — some designs' largest embedded
## texture is actually a thin border strip or a decal, not the base paper. Godot's own
## glTF import already composites all of that correctly via the mesh's real UVs and
## material blend modes, so rendering the model is the faithful way to flatten it back
## to a 2D card, matching how it actually looks in-game.
##
## Run windowed (needs real GPU rendering, not `--headless`):
##   $GODOT_BIN --path . res://scenes/dev/letter_paper_bake.tscn

const OUT_DIR := "res://assets/generated/ui/letter"
const PAPER_COUNT := 64
const PX_PER_UNIT := 2200.0 ## raw model units are meters at pipeline scale=0.001; ~0.25m card -> ~550px
const MARGIN := 1.04


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var baked := 0
	for paper_type in range(PAPER_COUNT):
		var stem := "lat_letter%02d" % (paper_type + 1)
		var path := "res://assets/generated/environment/%s.glb" % stem
		if not ResourceLoader.exists(path):
			print("letter_paper_bake: skip paper_type %d (%s missing)" % [paper_type, stem])
			continue
		var img: Image = await _bake_one(path)
		if img == null:
			print("letter_paper_bake: FAILED paper_type %d (%s)" % [paper_type, stem])
			continue
		var abs_dest := ProjectSettings.globalize_path(OUT_DIR) + "/paper%02d.png" % (paper_type + 1)
		img.save_png(abs_dest)
		baked += 1
	print("letter_paper_bake: baked %d/%d paper textures -> %s" % [baked, PAPER_COUNT, OUT_DIR])
	get_tree().quit()


func _bake_one(path: String) -> Variant:
	var model: Node3D = load(path).instantiate()
	add_child(model)
	_force_unshaded(model)

	var aabb := _combined_aabb(model)
	if aabb.size.x <= 0.0 or aabb.size.y <= 0.0:
		model.queue_free()
		return null

	var w := int(ceil(aabb.size.x * PX_PER_UNIT))
	var h := int(ceil(aabb.size.y * PX_PER_UNIT))
	w = clampi(w, 8, 2048)
	h = clampi(h, 8, 2048)

	var sub := SubViewport.new()
	sub.size = Vector2i(w, h)
	sub.transparent_bg = true
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 1.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	sub.add_child(world_env)
	add_child(sub)

	model.reparent(sub)

	var cam := Camera3D.new()
	sub.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = aabb.size.y * MARGIN
	var center := aabb.get_center()
	cam.position = Vector3(center.x, center.y, 1.0)
	cam.rotation = Vector3.ZERO ## looking down -Z, matching the flat card's own facing
	cam.current = true
	cam.near = 0.01
	cam.far = 10.0

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := sub.get_texture().get_image()
	_patch_decode_black(img)

	sub.queue_free()
	return img


## Some stationeries reference a shared decal texture (`lat_tegami_fusen_tex` and
## similarly-formatted decals) that decodes with a correct alpha shape but zeroed RGB —
## a known texture-decode gap (see `docs/asset_pipeline.md`'s IA4/IA8 nibble-order
## notes), not a real design element. Repaint fully-opaque near-black pixels as a
## plain cream paper tone rather than surfacing that bug as a black blob in-game.
const _BLACK_THRESHOLD := 10
const _PATCH_COLOR := Color(0.97, 0.95, 0.88, 1.0)


func _patch_decode_black(img: Image) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.78 and c.r * 255.0 < _BLACK_THRESHOLD and c.g * 255.0 < _BLACK_THRESHOLD and c.b * 255.0 < _BLACK_THRESHOLD:
				img.set_pixel(x, y, _PATCH_COLOR)


func _force_unshaded(root: Node) -> void:
	for mi in _mesh_instances(root):
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var mat: Material = mi.get_active_material(i)
			if mat is BaseMaterial3D:
				(mat as BaseMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func _mesh_instances(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_mesh_instances(c))
	return out


func _combined_aabb(root: Node) -> AABB:
	var aabb: AABB
	var first := true
	for mi: MeshInstance3D in _mesh_instances(root):
		var b: AABB = mi.transform * mi.get_aabb()
		if first:
			aabb = b
			first = false
		else:
			aabb = aabb.merge(b)
	return aabb
