class_name TownMap
extends RefCounted

## Town map acre tiles + labels from `m_map_ovl` / `kan_tizu_*`.
## Textures live under `assets/generated/ui/map/` (pipeline `--kind map-ui`).

const TILES_DIR := "res://assets/generated/ui/map/tiles"
const CHROME_DIR := "res://assets/generated/ui/map/chrome"
const CATALOG_PATH := "res://assets/generated/ui/map/catalog.json"

## Display size of one acre tile. Native CI is 32×32; 2× nearest keeps seams crisp.
const TILE_PX := 64
const NATIVE_TILE_PX := 32
const CURSOR_FRAMES := 18

## Decomp `l_map_pal` / stems for `mFM_BLOCK_TYPE_*`. Godot compact ids remap first.
static var _stems: PackedStringArray = PackedStringArray()
static var _pals: PackedByteArray = PackedByteArray()
static var _tex_cache: Dictionary = {}


static func assets_ready() -> bool:
	return ResourceLoader.exists(TILES_DIR + "/f_p0.png")


static func ensure_tables() -> void:
	if not _stems.is_empty():
		return
	if ResourceLoader.exists(CATALOG_PATH):
		var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				var stems: Variant = parsed.get("block_stems", [])
				var pals: Variant = parsed.get("block_pals", [])
				if stems is Array and pals is Array and stems.size() == pals.size():
					for s: Variant in stems:
						_stems.append(str(s))
					for p: Variant in pals:
						_pals.append(clampi(int(p), 0, 1) as int)
					return
	_stems = PackedStringArray()
	_pals = PackedByteArray()


## Map Godot `TownFieldGenerator` acre ids onto decomp `mFM_BLOCK_TYPE_*` indices.
static func decomp_block_type(godot_type: int) -> int:
	match godot_type:
		TownFieldGenerator.T_BORDER_CLIFF_OCEAN_LEFT:
			return 80
		TownFieldGenerator.T_BORDER_CLIFF_OCEAN_RIGHT:
			return 81
		TownFieldGenerator.T_MUSEUM:
			return 84
		TownFieldGenerator.T_NEEDLEWORK:
			return 85
		TownFieldGenerator.T_PORT:
			return 100
		_:
			return godot_type


static func tile_path_for_type(godot_type: int) -> String:
	ensure_tables()
	var dtype: int = decomp_block_type(godot_type)
	var stem := "f"
	var pal := 0
	if dtype >= 0 and dtype < _stems.size():
		stem = _stems[dtype]
		pal = int(_pals[dtype])
	return "%s/%s_p%d.png" % [TILES_DIR, stem, pal]


static func load_tile(godot_type: int) -> Texture2D:
	var path: String = tile_path_for_type(godot_type)
	if _tex_cache.has(path):
		return _tex_cache[path] as Texture2D
	if not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path) as Texture2D
	_tex_cache[path] = tex
	return tex


static func load_chrome(name: String) -> Texture2D:
	var path := "%s/%s.png" % [CHROME_DIR, name]
	if _tex_cache.has(path):
		return _tex_cache[path] as Texture2D
	if not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path) as Texture2D
	_tex_cache[path] = tex
	return tex


## Paste FG acres into one atlas so neighbouring tiles share edges (no Control gaps).
static func compose_fg_texture(types: PackedByteArray) -> Texture2D:
	var cols: int = TownFieldGenerator.FG_X_NUM
	var rows: int = TownFieldGenerator.FG_Z_NUM
	var expected: int = cols * rows
	if types.size() != expected:
		return null
	var img := Image.create(cols * NATIVE_TILE_PX, rows * NATIVE_TILE_PX, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.45, 0.75, 0.4, 1))
	for i: int in expected:
		var src: Image = _tile_image(int(types[i]))
		if src == null:
			continue
		var x: int = (i % cols) * NATIVE_TILE_PX
		var y: int = int(i / cols) * NATIVE_TILE_PX
		img.blit_rect(src, Rect2i(0, 0, mini(NATIVE_TILE_PX, src.get_width()), mini(NATIVE_TILE_PX, src.get_height())), Vector2i(x, y))
	return ImageTexture.create_from_image(img)


static func _tile_image(godot_type: int) -> Image:
	var path: String = tile_path_for_type(godot_type)
	var tex: Texture2D = load_tile(godot_type)
	if tex != null:
		var from_tex: Image = tex.get_image()
		if from_tex != null:
			if from_tex.get_format() != Image.FORMAT_RGBA8:
				from_tex = from_tex.duplicate()
				from_tex.convert(Image.FORMAT_RGBA8)
			return from_tex
	if ResourceLoader.exists(path):
		var loaded := Image.new()
		if loaded.load(path) == OK:
			if loaded.get_format() != Image.FORMAT_RGBA8:
				loaded.convert(Image.FORMAT_RGBA8)
			return loaded
	return null


## FG acre types in row-major A1…F5 order (`bz` 1..6, `bx` 1..5).
static func fg_acre_types(data: WorldData) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(TownFieldGenerator.FG_X_NUM * TownFieldGenerator.FG_Z_NUM)
	for i: int in out.size():
		out[i] = TownFieldGenerator.T_FLAT
	if data == null or data.acre_types.size() != TownFieldGenerator.BLOCK_TOTAL:
		return out
	var i := 0
	for bz: int in range(TownFieldGenerator.FG_Z0, TownFieldGenerator.FG_Z0 + TownFieldGenerator.FG_Z_NUM):
		for bx: int in range(TownFieldGenerator.FG_X0, TownFieldGenerator.FG_X0 + TownFieldGenerator.FG_X_NUM):
			out[i] = data.acre_types[bz * TownFieldGenerator.BLOCK_X + bx]
			i += 1
	return out


## Absolute block (`bx`,`bz`) → FG cursor indices (`sel_bx`,`sel_bz`), or (-1,-1).
static func fg_from_block(block: Vector2i) -> Vector2i:
	if not VillagerWalk.is_fg_block(block):
		return Vector2i(-1, -1)
	return Vector2i(block.x - TownFieldGenerator.FG_X0, block.y - TownFieldGenerator.FG_Z0)


static func block_from_fg(fg: Vector2i) -> Vector2i:
	return Vector2i(fg.x + TownFieldGenerator.FG_X0, fg.y + TownFieldGenerator.FG_Z0)


static func acre_code(fg: Vector2i) -> String:
	if fg.x < 0 or fg.y < 0:
		return "--"
	var letter := char(65 + fg.y) ## A–F
	return "%s-%d" % [letter, fg.x + 1]


static func label_for_acre(data: WorldData, fg: Vector2i) -> String:
	if data == null or fg.x < 0:
		return ""
	var block: Vector2i = block_from_fg(fg)
	var type: int = TownFieldGenerator.T_FLAT
	if data.acre_types.size() == TownFieldGenerator.BLOCK_TOTAL:
		type = int(data.acre_types[block.y * TownFieldGenerator.BLOCK_X + block.x])
	match type:
		TownFieldGenerator.T_TRACKS_STATION:
			return "Station"
		TownFieldGenerator.T_TRACKS_DUMP:
			return "Dump"
		TownFieldGenerator.T_PLAYER_HOUSE:
			return "Your house"
		TownFieldGenerator.T_TRACKS_SHOP:
			return "Shop"
		TownFieldGenerator.T_SHRINE:
			return "Wishing Well"
		TownFieldGenerator.T_TRACKS_POST:
			return "Post Office"
		TownFieldGenerator.T_POLICE:
			return "Police Station"
		TownFieldGenerator.T_MUSEUM:
			return "Museum"
		TownFieldGenerator.T_NEEDLEWORK:
			return "Able Sisters"
		TownFieldGenerator.T_PORT:
			return "Dock"
		_:
			pass
	for b: BuildingPlacement in data.buildings:
		if b == null:
			continue
		if VillagerWalk.block_from_cell(b.cell) != block:
			continue
		var id := String(b.id)
		if id.begins_with("npc_house_"):
			return "Villager house"
		if id == &"player_house":
			return "Your house"
	return TownFieldGenerator.acre_abbrev(type).strip_edges()


## Cursor pulse green channel 0–100 over `mMP_CURSOR_FRAMES` (decomp `col_g`).
static func cursor_green(frame: int) -> float:
	const COL_G: Array[int] = [0, 1, 2, 5, 10, 20, 50, 75, 90, 100, 90, 75, 50, 20, 10, 5, 2, 1]
	var i: int = posmod(frame, COL_G.size())
	return float(COL_G[i]) / 100.0


static func cursor_scale(frame: int) -> float:
	const SCALES: Array[float] = [
		1.0, 1.015, 1.03, 1.04, 1.05, 1.06, 1.07, 1.08, 1.09,
		1.1, 1.09, 1.08, 1.07, 1.06, 1.05, 1.04, 1.03, 1.015,
	]
	return SCALES[posmod(frame, SCALES.size())]
