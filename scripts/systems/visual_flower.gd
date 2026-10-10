class_name VisualFlower
extends RefCounted

## Field flower colour (`mFM_SetFGPal`): every flower shares one CI4 atlas, and its colour
## is TLUT slot `K` (white / purple / yellow pansy, …), bound each term to
## `mFM_obj_a_01_flower_pal[K * 9 + flower_pal_idx_table[term]]` — so a flower's colour
## shifts with the season. The pipeline writes one PNG per row (`obj_flower_tex_pNN`).

const ROW_TEX := "res://assets/generated/textures/rel/obj_flower_tex_p%02d.png"
## `mFM_SetFGPal` `flower_pal_idx_table[mTM_TERM_NUM]`.
const PAL_IDX: Array[int] = [8, 8, 8, 0, 1, 1, 1, 2, 2, 3, 4, 5, 6, 7, 8, 8, 8, 8]
const SPECIES: Array[String] = ["FLOWER_PANSIES", "FLOWER_COSMOS", "FLOWER_TULIP"]


## The colour slot (0–2) of a grown flower visual, or −1.
static func colour_of(visual_id: StringName) -> int:
	var id := String(visual_id)
	for prefix: String in SPECIES:
		if id.begins_with(prefix) and id.length() == prefix.length() + 1:
			return clampi(int(id.right(1)), 0, 2)
	return -1


## `flowerK_pal`'s row for colour `k` in calendar term `term`.
static func palette_row(k: int, term: int) -> int:
	return k * 9 + PAL_IDX[clampi(term, 0, PAL_IDX.size() - 1)]


static func apply(pivot: Node, visual_id: StringName, term: int = -1) -> bool:
	var k: int = colour_of(visual_id)
	if k < 0 or pivot == null:
		return false
	var row: int = palette_row(k, term if term >= 0 else Clock.term_idx())
	var path := ROW_TEX % row
	if not ResourceLoader.exists(path):
		return false
	var tex: Texture2D = load(path) as Texture2D
	var done := false
	for node: Node in pivot.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i: int in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(i) as StandardMaterial3D
			if mat == null or mat.albedo_texture == null:
				continue
			var std := mat.duplicate() as StandardMaterial3D
			## The tulip bake doubles the atlas to wrap its stem; tile the row to match.
			std.albedo_texture = VisualAtlas.tile_to_atlas(tex, VisualAtlas.albedo_size(mat))
			mi.set_surface_override_material(i, std)
			done = true
	return done
