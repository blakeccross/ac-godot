class_name InventoryChrome
extends RefCounted

## Pocket window chrome from `m_inventory_ovl` / `inv_mwin_*`.
## Pipeline: `python3 tools/build_assets.py --step convert --kind inventory-ui`
## Prefers `assets/generated/ui/inventory/` (ACHD when enabled); falls back to
## `textures/rel/` then `assets/custom/ui/inventory/`.

const CHROME_DIR := "res://assets/generated/ui/inventory"
const REL_DIR := "res://assets/generated/textures/rel"
const CUSTOM_DIR := "res://assets/custom/ui/inventory"
const CATALOG_PATH := CHROME_DIR + "/catalog.json"

static var _tex_cache: Dictionary = {}
static var _catalog: Dictionary = {}
static var _catalog_loaded: bool = false


static func assets_ready() -> bool:
	return ResourceLoader.exists(CHROME_DIR + "/window_shell.png") or ResourceLoader.exists(
		CHROME_DIR + "/items_label.png"
	) or ResourceLoader.exists(CHROME_DIR + "/inv_mwin_items_tex.png")


static func load_catalog() -> Dictionary:
	if _catalog_loaded:
		return _catalog
	_catalog_loaded = true
	_catalog = {}
	if not FileAccess.file_exists(CATALOG_PATH):
		return _catalog
	var f: FileAccess = FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if f == null:
		return _catalog
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_catalog = parsed
	return _catalog


static func clear_cache() -> void:
	_tex_cache.clear()
	_catalog.clear()
	_catalog_loaded = false


static func load_tex(name: String) -> Texture2D:
	if _tex_cache.has(name):
		return _tex_cache[name] as Texture2D
	var paths: PackedStringArray = _candidate_paths(name)
	for path: String in paths:
		if ResourceLoader.exists(path):
			var tex: Texture2D = load(path) as Texture2D
			_tex_cache[name] = tex
			return tex
	_tex_cache[name] = null
	return null


## Pocket picture for a slot. Prefers authored `ItemData.icon`, then field
## `obj_item_*` cards (correct colors), then `inv_mwin_*` encyclopedia glyphs.
static func icon_for_item(
	data: ItemData, condition: InventoryItem.Condition = InventoryItem.Condition.NORMAL
) -> Texture2D:
	if condition == InventoryItem.Condition.PRESENT:
		var present: Texture2D = load_tex("item_present")
		if present == null:
			present = load_tex("item_pbox")
		if present != null:
			return present
	if data == null:
		return load_tex("item_leaf")
	if data.icon != null:
		return data.icon
	if data.category == ItemData.Category.CLOTH and data.cloth_index >= 0:
		var cloth_path: String = FieldCatalog.cloth_albedo(data.cloth_index)
		if cloth_path != "" and ResourceLoader.exists(cloth_path):
			var cloth_tex: Texture2D = load(cloth_path) as Texture2D
			if cloth_tex != null:
				return cloth_tex
	var stem: String = _item_icon_stem(data)
	var tex: Texture2D = load_tex(stem)
	if tex != null:
		return tex
	return load_tex("item_leaf")


static func _item_icon_stem(data: ItemData) -> String:
	## Prefer `obj_item_*` field cards — `inv_mwin_*` encyclopedia icons often bake
	## the wrong CI palette (green apple, blue disc, etc.).
	match String(data.id):
		"axe":
			return "item_axe"
		"shovel":
			return "item_shovel"
		"fishing_rod":
			return "item_rod"
		"net":
			return "item_net"
		"watering_can":
			return "item_akikan"
		"apple":
			return "item_apple"
		"apple_sapling":
			return "item_naegi"
		"flower":
			return "item_seed"
		"fossil":
			return "item_fossil"
		"honeycomb":
			return "item_matutake"
		"paper":
			return "item_paper"
		"money_100", "money_1000", "money_10000", "money_30000":
			return "item_bag"
		"wall_blue":
			return "item_kabe"
		"floor_tile":
			return "item_carpet"
		_:
			pass
	if data is ToolData:
		match (data as ToolData).kind:
			ToolData.Kind.AXE:
				return "item_axe"
			ToolData.Kind.SHOVEL:
				return "item_shovel"
			ToolData.Kind.FISHING_ROD:
				return "item_rod"
			ToolData.Kind.NET:
				return "item_net"
			ToolData.Kind.WATERING_CAN:
				return "item_akikan"
			_:
				pass
	match data.category:
		ItemData.Category.TOOL:
			return "item_leaf"
		ItemData.Category.FURNITURE:
			return "item_leaf"
		ItemData.Category.FRUIT:
			return "item_apple"
		ItemData.Category.FISH:
			return "item_fish"
		ItemData.Category.BUG:
			return "item_net"
		ItemData.Category.WALL:
			return "item_kabe"
		ItemData.Category.FLOOR:
			return "item_carpet"
		ItemData.Category.CLOTH:
			return "item_fuku"
		_:
			return "item_leaf"


static func _candidate_paths(name: String) -> PackedStringArray:
	var out: PackedStringArray = []
	out.append("%s/%s.png" % [CHROME_DIR, name])
	## Legacy / decomp stems still written by older extracts.
	var legacy: String = _legacy_stem(name)
	if legacy != name:
		out.append("%s/%s.png" % [CHROME_DIR, legacy])
	out.append("%s/%s.png" % [REL_DIR, legacy if legacy != "" else name])
	out.append("%s/%s.png" % [CUSTOM_DIR, name])
	return out


static func _legacy_stem(name: String) -> String:
	match name:
		"items_label":
			return "inv_mwin_items_tex"
		"letters_label":
			return "inv_mwin_letters_tex"
		"bells_label":
			return "inv_mwin_bells_tex"
		"portrait_frame":
			return "inv_mwin_3Dma_tex"
		"slot_ring":
			return "inv_mwin_nwaku_tex"
		"slot_item":
			return "inv_mwin_nwaku_tex_item_blue"
		"slot_letter":
			return "inv_mwin_nwaku_tex_letter_red"
		"tab_fish":
			return "inv_mwin_gturi_tex"
		"tab_bug":
			return "inv_mwin_gmushi_tex"
		"tab_scoop":
			return "inv_mwin_gscoop_tex"
		"tab_axe":
			return "inv_mwin_gono_tex"
		"tab_pencil":
			return "tab_pencil"
		"tab_face":
			return "tab_face"
		"letter":
			return "inv_mwin_mtegami_tex"
		"letter_present":
			return "inv_mwin_pmtegami_tex"
		"letter_open":
			return "inv_mwin_otegami_tex"
		"bells_frame":
			return "inv_mwin_suujiwaku1_tex"
		"paper":
			return "paper_cloth226"
		"name_bar":
			return "inv_mwin_sen_tex"
		"window_shell":
			return "window_shell"
		"item_ono":
			return "inv_mwin_ono_tex"
		"item_scoop":
			return "inv_mwin_scoop_tex"
		"item_turi":
			return "inv_mwin_turi_tex"
		"item_mushi":
			return "inv_mwin_mushi_tex"
		"item_akikan":
			return "inv_mwin_akikan_tex"
		"item_axe":
			return "obj_item_axe_tex"
		"item_shovel":
			return "obj_item_shovel_tex"
		"item_rod":
			return "obj_item_rod_tex"
		"item_net":
			return "obj_item_net_tex"
		"item_apple":
			return "obj_item_apple_tex"
		"item_naegi":
			return "inv_mwin_naegi_tex"
		"item_seed":
			return "obj_item_seed_tex"
		"item_kaseki":
			return "inv_mwin_kaseki_tex"
		"item_fossil":
			return "obj_item_fossil_tex"
		"item_matutake":
			return "obj_item_matutake_tex"
		"item_binsen1":
			return "inv_mwin_binsen1_tex"
		"item_paper":
			return "obj_item_paper_tex"
		"item_okane1":
			return "inv_mwin_okane1_tex"
		"item_okane2":
			return "inv_mwin_okane2_tex"
		"item_okane3":
			return "inv_mwin_okane3_tex"
		"item_okane4":
			return "inv_mwin_okane4_tex"
		"item_bag":
			return "obj_item_bag_tex"
		"item_kabe":
			return "inv_mwin_kabe_tex"
		"item_jyuutan":
			return "inv_mwin_jyuutan_tex"
		"item_carpet":
			return "obj_item_carpet_tex"
		"item_fuku3":
			return "inv_mwin_fuku3_tex"
		"item_fuku":
			return "obj_item_fuku_tex"
		"item_fish":
			return "obj_item_fish_tex"
		"item_pbox":
			return "inv_mwin_pbox_tex"
		"item_present":
			return "obj_item_present_tex"
		"item_leaf":
			return "obj_item_leaf_tex"
		_:
			return name
