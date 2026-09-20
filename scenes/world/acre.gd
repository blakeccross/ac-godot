class_name Acre
extends Node3D
## Root of a baked field acre scene (`scenes/world/acres/<id>.tscn`,
## written by `tools/bake_acre_scenes.gd`). The scene is the whole acre: mesh nodes with
## their materials already assigned (river / ocean / splash / wet-sand shaders included,
## textures as external PNGs), plus the unit grid. Only the season swap is left to runtime.
##
## A surface takes part in the season swap when its material carries a `field_role`
## (grass, earth, cliff, …) stamped at bake time. `atlas_cell` is the wrap-bake period,
## also stamped at bake time so no pixels are read here.

@export var visual_id: StringName = &""
@export var grid: AcreGrid

## `(path, target size, clamp, cell)` → re-tiled season sheet. Every acre in a town shares
## the same handful of tiles, so a season change re-tiles each one once, not once per acre.
static var _tile_cache: Dictionary = {}

var _slots: Array[Dictionary] = []
var _slots_built: bool = false


static func clear_tile_cache() -> void:
	_tile_cache.clear()


## Point every season-role surface at the current season's sheet (spring/summer, autumn,
## winter). With no pack on disk for a role the baked summer material stays.
func apply_season() -> void:
	_build_slots()
	for slot: Dictionary in _slots:
		var mesh_instance: MeshInstance3D = slot["mesh_instance"]
		var base: Material = slot["base"]
		var swapped: Material = _seasonal_material(base, String(slot["role"]))
		mesh_instance.set_surface_override_material(int(slot["surface"]), swapped if swapped != null else base)


func _build_slots() -> void:
	if _slots_built:
		return
	_slots_built = true
	for child: Node in get_children():
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		for surface: int in mesh_instance.mesh.get_surface_count():
			var base: Material = mesh_instance.get_surface_override_material(surface)
			if base == null or not base.has_meta("field_role"):
				continue
			_slots.append(
				{
					"mesh_instance": mesh_instance,
					"surface": surface,
					"base": base,
					"role": String(base.get_meta("field_role")),
				}
			)


static func _seasonal_material(base: Material, role: String) -> Material:
	var path: String = FieldCatalog.season_texture_path(role)
	if path.is_empty():
		return null
	var season_tex: Texture2D = load(path) as Texture2D
	if season_tex == null:
		return null
	if base is ShaderMaterial:
		return _seasonal_wet_sand(base as ShaderMaterial, path, season_tex)
	if base is StandardMaterial3D:
		return _seasonal_standard(base as StandardMaterial3D, role, path, season_tex)
	return null


static func _seasonal_standard(
	base: StandardMaterial3D, role: String, path: String, season_tex: Texture2D
) -> Material:
	var std := base.duplicate() as StandardMaterial3D
	var target: Vector2i = VisualAtlas.albedo_size(base)
	var cell: int = int(base.get_meta("atlas_cell", 0))
	std.albedo_texture = (
		_tiled(path, season_tex, target, FieldCatalog.season_tile_clamp_v(role), cell)
		if target != Vector2i.ZERO
		else season_tex
	)
	std.albedo_color = Color.WHITE
	std.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	std.texture_repeat = false
	return std


## Shore wet-sand band (`beach1` I4): the shader samples the sheet directly.
static func _seasonal_wet_sand(base: ShaderMaterial, path: String, season_tex: Texture2D) -> Material:
	if not base.has_meta("beach_wet"):
		return null
	var sh := base.duplicate() as ShaderMaterial
	var target := Vector2i.ZERO
	var current: Variant = sh.get_shader_parameter("albedo_texture")
	if current is Texture2D:
		target = Vector2i((current as Texture2D).get_width(), (current as Texture2D).get_height())
	sh.set_shader_parameter(
		"albedo_texture", _tiled(path, season_tex, target, true, 0) if target != Vector2i.ZERO else season_tex
	)
	return sh


static func _tiled(path: String, tile: Texture2D, target: Vector2i, clamp_v: bool, cell: int) -> Texture2D:
	var key := "%s|%d|%d|%d|%d" % [path, target.x, target.y, int(clamp_v), cell]
	var cached: Variant = _tile_cache.get(key)
	if cached is Texture2D:
		return cached as Texture2D
	var tiled: Texture2D = VisualAtlas.tile_to_atlas(tile, target, false, clamp_v, cell)
	_tile_cache[key] = tiled
	return tiled
