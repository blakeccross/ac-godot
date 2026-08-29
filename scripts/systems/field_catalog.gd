class_name FieldCatalog
extends RefCounted

## Decomp FG/BG identifiers → generated GLB paths.
## Names from `m_name_table.h` / `m_bg_type.h`. Meshes live in gitignored `assets/generated/`.

## Pipeline multiplies raw GX verts by this (`tools/config.example.json`). It is
## not the in-game draw scale: actors use 0.01, acre DLs use 0.0625.
const PIPELINE_SCALE := 0.001
## `m_actor.c` Actor_info_ct: `actor->scale = 0.01`.
const ACTOR_DRAW_SCALE := 0.01
## `ac_field_draw.c`: `Matrix_scale(0.0625)` undoes 16× acre display-list verts.
const FIELD_DRAW_SCALE := 0.0625
## `mFI_UNIT_BASE_SIZE` (40 GX) = one 2 m cell. Keep in sync with `WorldData.cell_size`.
const GX_TO_METERS := 0.05
const ACRE_METERS := 32.0
## Authored land datum in exported `grd_*` GLBs (40 GX × 16 × PIPELINE_SCALE).
const ACRE_MODEL_GROUND_Y := 0.64
## `mFI_BkNum2BaseHeight` = height × 3 × 40 GX.
const ACRE_STEP_METERS := 6.0
## Typical grass `center` in `mCoBG_CollisionData_c` (40 GX = one cell).
const LAND_COUNTS := 4
## Each height count is ×10 GX (`mCoBG`).
const COUNTS_TO_METERS := 10.0 * GX_TO_METERS
## `mCoBG_HEIGHT_MAX`. TRACKS dummy combos fill the acre with this.
const HEIGHT_MAX := 31
const UNIT_STRIDE := 7
const UNITS_PER_ACRE := 256
## Acre DLs that sample `bridge_1_tex` (stone). `bridge_2_tex` is wood planks.
const _STONE_BRIDGE_BG: PackedStringArray = [
	"grd_s_r1_b_1",
	"grd_s_r2_b_1",
	"grd_s_r3_b_1",
	"grd_s_r3_b_3",
	"grd_s_r4_b_1",
	"grd_s_r5_b_1",
	"grd_s_r6_b_1",
	"grd_s_r7_b_1",
	"grd_s_m_r1_b_1",
	"grd_s_m_r1_b_3",
]

const GENERATED_ROOT := "res://assets/generated/"

static var _units_cache: Dictionary = {}


static func season_letter() -> String:
	if Clock == null:
		return "s"
	match Clock.season():
		ClockService.Season.WINTER:
			return "w"
		ClockService.Season.AUTUMN:
			return "f"
		_:
			return "s"


static func mesh_paths(visual_id: StringName) -> PackedStringArray:
	var id := String(visual_id)
	if id.begins_with("grd_"):
		return _existing(["environment/acres/%s.glb" % id])
	if id.begins_with("tol_"):
		return _existing(["items/%s.glb" % id])
	match visual_id:
		&"obj_s_tree5", &"TREE":
			return _existing([_seasonal_tree("obj_%s_tree5")])
		&"obj_s_stump5", &"TREE_STUMP004":
			var stump := _existing([_seasonal_tree("obj_%s_stump5")])
			if stump.is_empty():
				stump = _existing(["environment/trees/obj_s_stump5.glb"])
			return stump
		&"obj_hole0", &"HOLE00":
			## Flat grass hole (`HOLE00` / `obj_hole0`). Slope variants HOLE01–24 wait.
			## Prefer the paletted convert; do not also instance the old untextured GLB.
			var hole: PackedStringArray = _existing(["environment/holes/obj_hole0.glb"])
			if hole.is_empty():
				hole = _existing(["environment/obj_hole0.glb"])
			return hole
		&"obj_s_tree5_apple", &"TREE_APPLE_FRUIT":
			var paths := _existing([_seasonal_tree("obj_%s_tree5")])
			paths.append_array(_existing(["environment/trees/obj_s_tree5_apple.glb"]))
			return paths
		&"obj_s_cedar5", &"CEDAR_TREE":
			return _existing([_seasonal_env("obj_%s_cedar5")])
		&"obj_s_palm5", &"TREE_PALM":
			return _existing([_seasonal_env("obj_%s_palm5")])
		&"obj_s_palm5_coco", &"TREE_PALM_FRUIT":
			var palm := _existing([_seasonal_env("obj_%s_palm5")])
			palm.append_array(_existing([_seasonal_env("obj_%s_palm5_coco")]))
			return palm
		&"obj_s_kanban", &"SIGNBOARD":
			## Field sign is `obj_s_kanban` (`ac_sign`). Pipeline currently exports shop kanban.
			return _existing(["environment/obj_s_kanban.glb", "environment/obj_shop_kanban.glb"])
		&"obj_flower_a", &"FLOWER_PANSIES0":
			return _existing(["environment/flowers/obj_flower_a.glb"])
		&"obj_flower_b", &"FLOWER_PANSIES1":
			return _existing(["environment/flowers/obj_flower_b.glb"])
		&"obj_flower_c", &"FLOWER_PANSIES2":
			return _existing(["environment/flowers/obj_flower_c.glb"])
		&"obj_s_stoneA", &"ROCK_A":
			return _existing([_seasonal_rock("A")])
		&"obj_s_stoneB", &"ROCK_B":
			return _existing([_seasonal_rock("B")])
		&"obj_s_stoneC", &"ROCK_C":
			return _existing([_seasonal_rock("C")])
		&"obj_s_stoneD", &"ROCK_D":
			return _existing([_seasonal_rock("D")])
		&"obj_s_stoneE", &"ROCK_E":
			return _existing([_seasonal_rock("E")])
		&"int_sum_chair01":
			return _existing(["furniture/int_sum_chair01.glb"])
		_:
			## Outdoor structures (`obj_s_myhome1`, `obj_s_museum`, `obj_s_tailor`, …).
			if id.begins_with("obj_"):
				return _structure_paths(id)
			return PackedStringArray()


static func is_acre(visual_id: StringName) -> bool:
	return String(visual_id).begins_with("grd_")


## Godot scale for pipeline GLBs so 1 GX matches `GX_TO_METERS`.
static func actor_uniform_scale() -> float:
	return ACTOR_DRAW_SCALE / PIPELINE_SCALE * GX_TO_METERS


static func acre_uniform_scale() -> float:
	return FIELD_DRAW_SCALE / PIPELINE_SCALE * GX_TO_METERS


static func acre_ground_y_offset() -> float:
	return -ACRE_MODEL_GROUND_Y * acre_uniform_scale()


static func counts_to_y(count: int, acre_elev: int) -> float:
	return float(acre_elev) * ACRE_STEP_METERS + float(count - LAND_COUNTS) * COUNTS_TO_METERS


static func is_water_attr(attr: int) -> bool:
	## Wave / water / waterfall / river / sea (`mCoBG_ATTRIBUTE_*`). Banks stay walkable.
	return (
		(attr >= 11 and attr <= 21)
		or attr == 24
		or attr == 25
		or attr == 26
		or (attr >= 36 and attr <= 38)
	)


static func is_bridge_attr(attr: int) -> bool:
	## Wood 27–31 and stone 32–35 (`mCoBG_ATTRIBUTE_*`). Walkable deck, not water.
	return is_wood_bridge_attr(attr) or is_stone_bridge_attr(attr)


static func is_wood_bridge_attr(attr: int) -> bool:
	return attr >= 27 and attr <= 31


static func is_stone_bridge_attr(attr: int) -> bool:
	return attr >= 32 and attr <= 35


static func is_stone_bridge_visual(visual_id: StringName) -> bool:
	## `bridge_1_tex` acres (`data_combi` / acre DLs). `_b_1` is stone except
	## `grd_s_r3_b_3` and beach `grd_s_m_r1_b_3`, which also use that tex.
	return _STONE_BRIDGE_BG.has(String(visual_id))


static func is_hole_attr(attr: int) -> bool:
	return attr == 10


static func is_sand_attr(attr: int) -> bool:
	return attr == 22


static func is_plantable_attr(attr: int) -> bool:
	## Grass0–3 and soil0–2. Stone, bush, hole, water, wood, and banks kill plants.
	return attr >= 0 and attr <= 6


static func is_slate_unit(slate: int, attr: int) -> bool:
	return slate != 0 or attr == 63


static func has_acre_collision(visual_id: StringName) -> bool:
	return acre_units(visual_id).size() == UNITS_PER_ACRE * UNIT_STRIDE


static func acre_units(visual_id: StringName) -> PackedByteArray:
	var id := String(visual_id)
	if id.is_empty():
		return PackedByteArray()
	if _units_cache.has(id):
		return _units_cache[id]
	var packed := _load_acre_units(id)
	_units_cache[id] = packed
	return packed


static func unit_at(visual_id: StringName, ux: int, uz: int) -> Dictionary:
	if ux < 0 or ux >= 16 or uz < 0 or uz >= 16:
		return {}
	var packed: PackedByteArray = acre_units(visual_id)
	if packed.size() != UNITS_PER_ACRE * UNIT_STRIDE:
		return {}
	var o: int = (uz * 16 + ux) * UNIT_STRIDE
	return {
		"c": packed[o],
		"nw": packed[o + 1],
		"sw": packed[o + 2],
		"se": packed[o + 3],
		"ne": packed[o + 4],
		"s": packed[o + 5],
		"a": packed[o + 6],
	}


static func _load_acre_units(id: String) -> PackedByteArray:
	var path := GENERATED_ROOT + "environment/acres/%s.col.json" % id
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return PackedByteArray()
	var units: Variant = (parsed as Dictionary).get("units", [])
	if typeof(units) != TYPE_ARRAY or (units as Array).size() != UNITS_PER_ACRE:
		return PackedByteArray()
	var packed := PackedByteArray()
	packed.resize(UNITS_PER_ACRE * UNIT_STRIDE)
	var i := 0
	for u: Variant in units:
		if typeof(u) != TYPE_DICTIONARY:
			return PackedByteArray()
		var d: Dictionary = u
		packed[i] = clampi(int(d.get("c", LAND_COUNTS)), 0, 31)
		packed[i + 1] = clampi(int(d.get("nw", LAND_COUNTS)), 0, 31)
		packed[i + 2] = clampi(int(d.get("sw", LAND_COUNTS)), 0, 31)
		packed[i + 3] = clampi(int(d.get("se", LAND_COUNTS)), 0, 31)
		packed[i + 4] = clampi(int(d.get("ne", LAND_COUNTS)), 0, 31)
		packed[i + 5] = clampi(int(d.get("s", 0)), 0, 1)
		packed[i + 6] = clampi(int(d.get("a", 0)), 0, 63)
		i += UNIT_STRIDE
	if _is_height_max_filler(packed):
		return PackedByteArray()
	return packed


static func _is_height_max_filler(packed: PackedByteArray) -> bool:
	## Dummy `GRD_*_1` TRACKS rows reuse an acre mesh with HEIGHT_MAX floors.
	if packed.size() != UNITS_PER_ACRE * UNIT_STRIDE:
		return false
	var n_max := 0
	for u: int in UNITS_PER_ACRE:
		if packed[u * UNIT_STRIDE] >= HEIGHT_MAX:
			n_max += 1
	return n_max > UNITS_PER_ACRE / 2


## Pick a concrete `grd_*` for an `mFM_BLOCK_TYPE_*` (`mRF_SelectBlock` / `data_combi`).
## `used` is already-chosen BG names this town (`l_use_data`); prefer an unused row.
static func acre_for_block_type(
	block_type: int, variant: int = 0, used: PackedStringArray = PackedStringArray()
) -> StringName:
	var candidates: PackedStringArray = _acre_candidates(block_type)
	if candidates.is_empty():
		candidates = PackedStringArray(["grd_s_f_1", "grd_s_f_2", "grd_s_f_3"])
	var pool: PackedStringArray = PackedStringArray()
	for name: String in candidates:
		var col_path := GENERATED_ROOT + "environment/acres/%s.col.json" % name
		if FileAccess.file_exists(col_path) and not has_acre_collision(StringName(name)):
			continue
		pool.append(name)
	if pool.is_empty():
		pool = candidates
	var with_mesh := PackedStringArray()
	for name: String in pool:
		if ResourceLoader.exists(GENERATED_ROOT + "environment/acres/%s.glb" % name):
			with_mesh.append(name)
	if not with_mesh.is_empty():
		pool = with_mesh
	var unused: PackedStringArray = PackedStringArray()
	for name: String in pool:
		if not used.has(name):
			unused.append(name)
	var pick_from: PackedStringArray = unused if not unused.is_empty() else pool
	var idx: int = posmod(variant, pick_from.size())
	return StringName(pick_from[idx])


static func _acre_candidates(block_type: int) -> PackedStringArray:
	## Prefix families from `data_combi.c` / available `assets/generated/environment/acres/`.
	match block_type:
		TownFieldGenerator.T_FLAT:
			return _names("grd_s_f_", 1, 10)
		TownFieldGenerator.T_PLAYER_HOUSE:
			return _names("grd_s_f_mh_", 1, 3)
		TownFieldGenerator.T_MUSEUM:
			return _names("grd_s_f_mu_", 1, 3)
		TownFieldGenerator.T_POLICE:
			return _names("grd_s_f_pk_", 1, 3)
		TownFieldGenerator.T_SHRINE:
			return _names("grd_s_f_ko_", 1, 3)
		TownFieldGenerator.T_RIVER_S:
			return _names("grd_s_r1_", 1, 4)
		TownFieldGenerator.T_RIVER_E:
			return _names("grd_s_r2_", 1, 4)
		TownFieldGenerator.T_RIVER_W:
			return _names("grd_s_r3_", 1, 4)
		TownFieldGenerator.T_RIVER_SE:
			return _names("grd_s_r4_", 1, 3)
		TownFieldGenerator.T_RIVER_ES:
			return _names("grd_s_r5_", 1, 3)
		TownFieldGenerator.T_RIVER_SW:
			return _names("grd_s_r6_", 1, 3)
		TownFieldGenerator.T_RIVER_WS:
			return _names("grd_s_r7_", 1, 3)
		TownFieldGenerator.T_BEACH:
			return _names("grd_s_m_", 1, 10)
		TownFieldGenerator.T_BEACH_RIVER:
			return _names("grd_s_m_r1_", 1, 5)
		TownFieldGenerator.T_BEACH_RIVER_BRIDGE:
			## `data_combi`: `_1`/`_3` stone (`bridge_1`), `_2` wood (`bridge_2`).
			return _names("grd_s_m_r1_b_", 1, 3)
		TownFieldGenerator.T_RIVER_S_BRIDGE:
			return _names("grd_s_r1_b_", 1, 3)
		TownFieldGenerator.T_RIVER_E_BRIDGE:
			return _names("grd_s_r2_b_", 1, 3)
		TownFieldGenerator.T_RIVER_W_BRIDGE:
			## `_3` is stone here (`grd_s_r3_b_3` / `bridge_1_tex`).
			return _names("grd_s_r3_b_", 1, 3)
		TownFieldGenerator.T_RIVER_SE_BRIDGE:
			return _names("grd_s_r4_b_", 1, 2)
		TownFieldGenerator.T_RIVER_ES_BRIDGE:
			return _names("grd_s_r5_b_", 1, 2)
		TownFieldGenerator.T_RIVER_SW_BRIDGE:
			return _names("grd_s_r6_b_", 1, 2)
		TownFieldGenerator.T_RIVER_WS_BRIDGE:
			return _names("grd_s_r7_b_", 1, 2)
		TownFieldGenerator.T_NEEDLEWORK:
			return _names("grd_s_m_ta_", 1, 3)
		TownFieldGenerator.T_PORT:
			## `data_combi`: PORT is the wharf (`grd_s_m_wf_*`), not the tailor lot.
			return _names("grd_s_m_wf_", 1, 3)
		TownFieldGenerator.T_TRACKS_DUMP:
			return _names("grd_s_t_", 1, 10)
		TownFieldGenerator.T_TRACKS_STATION:
			return _names("grd_s_t_st1_", 1, 3)
		TownFieldGenerator.T_TRACKS_SHOP:
			return _names("grd_s_t_sh_", 1, 3)
		TownFieldGenerator.T_TRACKS_POST:
			return _names("grd_s_t_po_", 1, 3)
		TownFieldGenerator.T_TRACKS_RIVER:
			return _names("grd_s_t_r1_", 1, 5)
		TownFieldGenerator.T_CLIFF_H:
			return _names("grd_s_c1_", 1, 5)
		TownFieldGenerator.T_CLIFF_BR:
			return _names("grd_s_c2_", 1, 3)
		TownFieldGenerator.T_CLIFF_VR:
			return _names("grd_s_c3_", 1, 3)
		TownFieldGenerator.T_CLIFF_TR:
			return _names("grd_s_c4_", 1, 3)
		TownFieldGenerator.T_CLIFF_TL:
			return _names("grd_s_c5_", 1, 3)
		TownFieldGenerator.T_CLIFF_VL:
			return _names("grd_s_c6_", 1, 3)
		TownFieldGenerator.T_CLIFF_BL:
			return _names("grd_s_c7_", 1, 3)
		TownFieldGenerator.T_SLOPE_H:
			return _names("grd_s_c1_s_", 1, 4)
		TownFieldGenerator.T_WF_H:
			return _names("grd_s_c1_r1_", 1, 3)
		TownFieldGenerator.T_WF_BR:
			return _names("grd_s_c2_r1_", 1, 2)
		TownFieldGenerator.T_RIV_CLIFF_VR:
			return _names("grd_s_c3_r1_", 1, 2)
		TownFieldGenerator.T_RIV_CLIFF_TR:
			return _names("grd_s_c4_r1_", 1, 2)
		TownFieldGenerator.T_WF_TL:
			return _names("grd_s_c5_r1_", 1, 2)
		TownFieldGenerator.T_RIV_CLIFF_VL:
			return _names("grd_s_c6_r1_", 1, 2)
		TownFieldGenerator.T_RIV_CLIFF_BL:
			return _names("grd_s_c7_r1_", 1, 2)
		TownFieldGenerator.T_RIV_CLIFF_H:
			return _names("grd_s_c1_r2_", 1, 3)
		TownFieldGenerator.T_WF_E_BR:
			return _names("grd_s_c2_r2_", 1, 2)
		TownFieldGenerator.T_WF_E_VR:
			return _names("grd_s_c3_r2_", 1, 2)
		TownFieldGenerator.T_RIV_E_TR:
			return _names("grd_s_c4_r2_", 1, 2)
		TownFieldGenerator.T_RIV_E_TL:
			return _names("grd_s_c5_r2_", 1, 2)
		TownFieldGenerator.T_RIV_W_H:
			return _names("grd_s_c1_r3_", 1, 3)
		TownFieldGenerator.T_RIV_W_TR:
			return _names("grd_s_c4_r3_", 1, 2)
		TownFieldGenerator.T_RIV_W_TL:
			return _names("grd_s_c5_r3_", 1, 2)
		TownFieldGenerator.T_WF_W_VL:
			return _names("grd_s_c6_r3_", 1, 1)
		TownFieldGenerator.T_WF_W_BL:
			return _names("grd_s_c7_r3_", 1, 2)
		_:
			if block_type >= TownFieldGenerator.T_SLOPE_H and block_type <= TownFieldGenerator.T_SLOPE_H + 6:
				var cliff_i: int = block_type - TownFieldGenerator.T_SLOPE_H + 1
				return _names("grd_s_c%d_s_" % cliff_i, 1, 3)
			## Pool_* = river + 29
			if block_type >= 69 and block_type <= 75:
				var pool: int = block_type - 69 + 1
				return _names("grd_s_r%d_p_" % pool, 1, 1)
			return _names("grd_s_f_", 1, 10)


static func _names(prefix: String, lo: int, hi: int) -> PackedStringArray:
	var out := PackedStringArray()
	for i: int in range(lo, hi + 1):
		out.append("%s%d" % [prefix, i])
	return out


static func villager_path(species: StringName) -> String:
	var code := _species_code(species)
	if code.is_empty():
		return ""
	return _first_existing(["characters/villagers/%s_1.glb" % code])


static func item_albedo(item_id: StringName) -> String:
	match item_id:
		&"apple":
			return _first_existing(["textures/rel/obj_item_apple_tex.png"])
		_:
			return ""


static func default_visual(kind: StringName) -> StringName:
	match kind:
		&"tree":
			return &"TREE_APPLE_FRUIT"
		&"house":
			## Villager home (`ac_house`). Player house sets `obj_s_myhome1` explicitly.
			return &"obj_s_house1"
		&"building":
			return &""
		&"shop":
			return &"obj_s_shop1"
		&"sign":
			return &"SIGNBOARD"
		&"furniture":
			return &"int_sum_chair01"
		&"flower":
			return &"FLOWER_PANSIES0"
		&"rock":
			return &"ROCK_A"
		&"hole":
			return &"HOLE00"
		_:
			return &""


static func _species_code(species: StringName) -> String:
	match species:
		&"squirrel":
			return "squ"
		&"cat":
			return "cat"
		&"bear":
			return "bea"
		&"cub":
			return "cbr"
		&"dog":
			return "dog"
		&"duck":
			return "duk"
		&"bird":
			return "brd"
		_:
			return String(species)


static func _structure_paths(id: String) -> PackedStringArray:
	## Summer `obj_s_*` → winter `obj_w_*` when that GLB exists (`structure_pal` seasons).
	var seasonal := id
	if id.begins_with("obj_s_") or id.begins_with("obj_w_") or id.begins_with("obj_f_"):
		seasonal = "obj_%s_%s" % [season_letter(), id.substr(6)]
	var paths: PackedStringArray = _existing(["environment/%s.glb" % seasonal])
	if paths.is_empty() and seasonal != id:
		paths = _existing(["environment/%s.glb" % id])
	return paths


static func _seasonal_tree(pattern: String) -> String:
	return "environment/trees/" + (pattern % season_letter()) + ".glb"


static func _seasonal_env(pattern: String) -> String:
	return "environment/" + (pattern % season_letter()) + ".glb"


static func _seasonal_rock(letter: String) -> String:
	return "environment/rocks/obj_%s_stone%s.glb" % [season_letter(), letter]


static func _existing(rel_paths: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for rel: Variant in rel_paths:
		var abs_path: String = GENERATED_ROOT + String(rel)
		if ResourceLoader.exists(abs_path) and not out.has(abs_path):
			out.append(abs_path)
	return out


static func _first_existing(rel_paths: Array) -> String:
	var found: PackedStringArray = _existing(rel_paths)
	if found.is_empty():
		return ""
	return found[0]
