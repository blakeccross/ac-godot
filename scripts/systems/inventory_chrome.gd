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
		_:
			return name
