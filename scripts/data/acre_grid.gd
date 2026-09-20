class_name AcreGrid
extends Resource
## One field acre's 16×16 unit table (`mCoBG_Collision_c`): per-unit corner heights, slate
## flag and attribute. Baked from the pipeline's `<id>.col.json` by
## `tools/bake_acre_scenes.gd` and referenced by the acre scene's `Acre` root, so a scene
## carries its own grid. Empty `units` marks a filler acre (see `_is_height_max_filler`).

@export var acre_id: StringName = &""
## `FieldCatalog.UNIT_STRIDE` bytes per unit, row-major (`z * 16 + x`):
## center, nw, sw, se, ne heights (0–31), slate flag, attribute (0–63).
@export var units: PackedByteArray = PackedByteArray()


func is_valid() -> bool:
	return units.size() == FieldCatalog.UNITS_PER_ACRE * FieldCatalog.UNIT_STRIDE


## Bake-time: parse the pipeline sidecar. Null when the acre has none; `units` is empty
## when the sidecar is malformed or the acre is a filler.
static func from_col_json(id: String) -> AcreGrid:
	var path := FieldCatalog.GENERATED_ROOT + "environment/acres/%s.col.json" % id
	if not FileAccess.file_exists(path):
		return null
	var grid := AcreGrid.new()
	grid.acre_id = StringName(id)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return grid
	var rows: Variant = (parsed as Dictionary).get("units", [])
	if typeof(rows) != TYPE_ARRAY or (rows as Array).size() != FieldCatalog.UNITS_PER_ACRE:
		return grid
	var packed := PackedByteArray()
	packed.resize(FieldCatalog.UNITS_PER_ACRE * FieldCatalog.UNIT_STRIDE)
	var i := 0
	for row: Variant in rows:
		if typeof(row) != TYPE_DICTIONARY:
			return grid
		var d: Dictionary = row
		packed[i] = clampi(int(d.get("c", FieldCatalog.LAND_COUNTS)), 0, 31)
		packed[i + 1] = clampi(int(d.get("nw", FieldCatalog.LAND_COUNTS)), 0, 31)
		packed[i + 2] = clampi(int(d.get("sw", FieldCatalog.LAND_COUNTS)), 0, 31)
		packed[i + 3] = clampi(int(d.get("se", FieldCatalog.LAND_COUNTS)), 0, 31)
		packed[i + 4] = clampi(int(d.get("ne", FieldCatalog.LAND_COUNTS)), 0, 31)
		packed[i + 5] = clampi(int(d.get("s", 0)), 0, 1)
		packed[i + 6] = clampi(int(d.get("a", 0)), 0, 63)
		i += FieldCatalog.UNIT_STRIDE
	if not _is_height_max_filler(id, packed):
		grid.units = packed
	return grid


static func _is_height_max_filler(id: String, packed: PackedByteArray) -> bool:
	## Dummy TRACKS `data_bgd` rows reuse a field mesh (`grd_s_c1_3`, …) with an
	## all-HEIGHT_MAX floor. Border cliffs (`grd_*_e*`) are authored as solid walls
	## (and tunnels keep a walkable strip) — those are real tables, not fillers.
	if FieldCatalog.is_border_edge_acre(id):
		return false
	var n_max := 0
	for u: int in FieldCatalog.UNITS_PER_ACRE:
		if packed[u * FieldCatalog.UNIT_STRIDE] >= FieldCatalog.HEIGHT_MAX:
			n_max += 1
	return n_max > FieldCatalog.UNITS_PER_ACRE / 2
