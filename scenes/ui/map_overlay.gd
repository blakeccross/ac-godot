extends CanvasLayer

## Town map submenu (`m_map_ovl.c`), drawn like `mMP_set_dl` in 320x240 screen units from
## layers `menu_ui.py` bakes into `ui/map_screen/`: the window (`kan_win_model`, yellow for
## the sight-map board, blue for the map item — `kan_win_color0/1_mode`), the acre tiles
## (`kan_tizu`, 22 units a side from (11.7, 45.7)), the second window with the selected
## acre's letter and number and the label frame sized to the label count, the label icons
## and words, the villager-house marks, the "you are here" mark and the pulsing cursor.
##
## ←↑→↓ (C-stick) move the cursor one acre, easing there (`add_calc` 0.7, 19, 1.8) before
## the next move; Escape / the map key close it. Opens from the top, closes to the top.

const TEX_DIR := "res://assets/generated/ui/map_screen/%s.png"
const SCREEN_BOUNDS := Rect2(-160.0, 120.0, 320.0, 240.0)
const MARK_BOUNDS := Rect2(-16.0, 16.0, 32.0, 32.0)
const BLOCK := 22.0
const MAP_ORIGIN := Vector2(11.7, 45.7)
const LETTERS := "abcdef"
## `mMP_set_house_dl`: villager marks by house position (column / row inside the acre).
const HOUSE_OFS_X: Array[float] = [5.0, 13.0, 17.0]
const HOUSE_OFS_Y: Array[float] = [-4.0, -11.0, -18.0]
## `land_color`: the town name, board / item.
const LAND_COLOR: Array[Color] = [Color8(255, 0, 255), Color8(60, 60, 255)]
const NAME_COLOR := Color8(255, 75, 40)
const FREE_COLOR := Color8(165, 145, 140)
const WORD_COLOR := Color8(120, 95, 205)
const FONT_PX := 16
const PLAYER_NUM := 4
const FREE_NAME := "free"

enum MapLabel { NPC, PLAYER, SHOP, POLICE, POST, SHRINE, STATION, JUNK, MUSEUM, NEEDLE, PORT }

## `mMP_label_data`: icon, icon offset, words ([text, x, y]; "" is the resident list).
const LABELS := {
	MapLabel.NPC: ["npcT_1", Vector2(-98, -24), [["", -92, -19]]],
	MapLabel.PLAYER: ["playerT", Vector2(-98, -26.5), [["", -92, -21.5]]],
	MapLabel.SHOP: ["omiseT", Vector2(-93, -30), [["Shop", -83, -25]]],
	MapLabel.POLICE: ["koubanT", Vector2(-93, -30), [["Police", -83, -19], ["Station", -83, -31]]],
	MapLabel.POST: ["yuuT", Vector2(-93, -30), [["Post", -83, -19], ["Office", -83, -31]]],
	MapLabel.SHRINE: ["yashiroT", Vector2(-93, -30), [["Wishing", -83, -19], ["Well", -83, -31]]],
	MapLabel.STATION: ["ekiT", Vector2(-93, -31), [["Train", -83, -19], ["Station", -83, -31]]],
	MapLabel.JUNK: ["gomiT", Vector2(-93, -30), [["Dump", -83, -25]]],
	MapLabel.MUSEUM: ["mu", Vector2(-93, -30), [["Museum", -83, -25]]],
	MapLabel.NEEDLE: ["ta", Vector2(-93, -30), [["Tailor", -83, -25]]],
	MapLabel.PORT: ["funeT", Vector2(-93, -30), [["Dock", -83, -25]]],
}
const ACRE_LABEL := {
	TownFieldGenerator.T_TRACKS_SHOP: MapLabel.SHOP,
	TownFieldGenerator.T_POLICE: MapLabel.POLICE,
	TownFieldGenerator.T_TRACKS_POST: MapLabel.POST,
	TownFieldGenerator.T_SHRINE: MapLabel.SHRINE,
	TownFieldGenerator.T_TRACKS_STATION: MapLabel.STATION,
	TownFieldGenerator.T_TRACKS_DUMP: MapLabel.JUNK,
	TownFieldGenerator.T_MUSEUM: MapLabel.MUSEUM,
	TownFieldGenerator.T_NEEDLEWORK: MapLabel.NEEDLE,
	TownFieldGenerator.T_PORT: MapLabel.PORT,
}

## Per acre: {label, residents: [{name, sex, layer, idx}]}.
var acres: Dictionary = {}
var sel: Vector2i = Vector2i.ZERO
var player_fg: Vector2i = Vector2i.ZERO
## 0 = the sight-map board, 1 = the map item (`menu->data0`).
var color_set: int = 1
var _open: bool = false
var _cursor := Vector2.ZERO
var _cursor_target := Vector2.ZERO
var _cursor_frame: int = 0
var _layout: WorldData = null
var _atlas: Texture2D = null
var _tex: Dictionary = {}
var _font: Font = null
var _accum: float = 0.0
## `m_map_ovl.c`: in from the top, out to the top.
var _slide: MenuSlide = null

@onready var _root: Control = $Root
@onready var _screen: Control = $Root/Screen
@onready var _canvas: Control = $Root/Screen/Canvas


func _ready() -> void:
	layer = 21
	add_to_group("map_ui")
	_slide = MenuSlide.attach(self)
	_root.visible = false
	_font = LetterBoard.load_font()
	_canvas.draw.connect(_draw_canvas)
	_root.resized.connect(_fit_screen)
	_fit_screen()
	set_process(false)


func _tex_of(name: String) -> Texture2D:
	if not _tex.has(name):
		var path := TEX_DIR % name
		_tex[name] = load(path) if ResourceLoader.exists(path) else null
	return _tex[name]


func _fit_screen() -> void:
	var sz := _root.size
	if sz.x <= 0.0 or sz.y <= 0.0:
		return
	var k := minf(sz.x / 320.0, sz.y / 240.0)
	_screen.scale = Vector2(k, k)
	_screen.position = (sz - Vector2(320, 240) * k) * 0.5


func is_open() -> bool:
	return _open


## `force` is the town's sight-map board (`mSM_OVL_MAP` mode 0): it shows the map without an item.
func open(force: bool = false) -> void:
	if _open:
		return
	if not force and Game != null and not Game.has_map:
		Game.post_notice("You don't have a town map yet.")
		return
	color_set = 0 if force else 1
	_layout = Game.resolve_world_data() if Game != null else null
	player_fg = _resolve_player_fg()
	sel = player_fg
	_cursor = Vector2(sel.x * BLOCK, -sel.y * BLOCK)
	_cursor_target = _cursor
	_cursor_frame = 0
	acres = build_labels(_layout)
	var types: PackedByteArray = TownMap.fg_acre_types(_layout)
	_atlas = TownMap.compose_fg_texture(types) if TownMap.assets_ready() else null
	_open = true
	Audio.play_se(&"17c")
	_root.visible = true
	set_process(true)
	_slide.slide_in(MenuSlide.Dir.IN_TOP)
	_canvas.queue_redraw()


func close() -> void:
	if not _open:
		return
	Audio.play_se(&"17d")
	_open = false
	_slide.slide_out(MenuSlide.Dir.OUT_TOP, _on_slid_out)


func _on_slid_out() -> void:
	if not _open:
		_root.visible = false
		set_process(false)


func toggle() -> void:
	if _open:
		close()
	else:
		open()


## `mMP_set_house_data` + `mMP_set_field_data`: who lives in each acre and which
## building labels the rest.
static func build_labels(data: WorldData) -> Dictionary:
	var out: Dictionary = {}
	if data == null:
		return out
	var owned: StringName = PlayerHouse.owned_building_id()
	for b: BuildingPlacement in data.buildings:
		if b == null:
			continue
		var id := String(b.id)
		var fg: Vector2i = TownMap.fg_from_block(VillagerWalk.block_from_cell(b.cell))
		if fg.x < 0:
			continue
		if id == String(PlayerHouse.DEFAULT_PLOT):
			var players: Array = []
			var has_player: bool = owned != &"" and Game != null
			for i: int in PLAYER_NUM:
				if i == 0 and has_player:
					players.append({"name": Game.player_name,
						"sex": 1 if Game.player_gender == IntroSequence.GENDER_FEMALE else 0, "layer": 0, "idx": 0})
				else:
					players.append({"name": FREE_NAME, "sex": -1, "layer": 0, "idx": 0})
			out[fg] = {"label": MapLabel.PLAYER, "residents": players}
		elif id.begins_with("npc_house_") and b.resident_id != &"":
			var v: VillagerData = VillagerCatalog.get_villager(b.resident_id)
			var entry: Dictionary = out.get(fg, {"label": MapLabel.NPC, "residents": []})
			if int(entry["label"]) != MapLabel.NPC:
				continue
			## The house's SIGN unit (one in from its NW corner) inside its 16-unit acre.
			var local := Vector2i(posmod(b.cell.x + 1, 16), posmod(b.cell.y + 1, 16))
			var col: int = clampi(local.x * 3 / 16, 0, 2)
			var row: int = clampi(local.y * 3 / 16, 0, 2)
			(entry["residents"] as Array).append({
				"name": v.display_name if v != null else String(b.resident_id),
				"sex": 0,
				"layer": _house_layer(data, b.cell),
				"idx": row * 3 + col,
			})
			out[fg] = entry
	## Villagers on lower ground first (`mMP_set_house_data`'s sort).
	for fg: Variant in out.keys():
		var e: Dictionary = out[fg]
		if int(e["label"]) == MapLabel.NPC:
			(e["residents"] as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return int(a["layer"]) < int(b["layer"]))
	if data.acre_types.size() == TownFieldGenerator.BLOCK_TOTAL:
		for z: int in TownFieldGenerator.FG_Z_NUM:
			for x: int in TownFieldGenerator.FG_X_NUM:
				var fg := Vector2i(x, z)
				if out.has(fg):
					continue
				var block: Vector2i = TownMap.block_from_fg(fg)
				var type: int = int(data.acre_types[block.y * TownFieldGenerator.BLOCK_X + block.x])
				if ACRE_LABEL.has(type):
					out[fg] = {"label": ACRE_LABEL[type], "residents": []}
	return out


## `mMP_check_layer`: the house mark's tint by how high its ground is — the lowest ground is
## layer 2, one up 1, the top 0, less one in a town without a third tier (as ours are).
static func _house_layer(data: WorldData, cell: Vector2i) -> int:
	var level: int = data.elevation_at(cell)
	return clampi(1 - level, 0, 2)


## Label count (`label_cnt`): residents for houses, 2 for buildings, 0 for none.
static func label_count(entry: Dictionary) -> int:
	if entry.is_empty():
		return 0
	var label: int = int(entry["label"])
	if label == MapLabel.NPC or label == MapLabel.PLAYER:
		return (entry["residents"] as Array).size()
	return 2


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("map"):
		if not _open and _blocked_by_other_ui():
			get_viewport().set_input_as_handled()
			return
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not _open:
		return
	if event.is_action_pressed("pause_menu") or event.is_action_pressed("ui_cancel") \
			or event.is_action_pressed("ui_accept"):
		close()
		get_viewport().set_input_as_handled()
		return
	if _cursor != _cursor_target or _slide.is_moving():
		return
	var step := Vector2i.ZERO
	if event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
		step = Vector2i(-1, 0)
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
		step = Vector2i(1, 0)
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("move_forward"):
		step = Vector2i(0, -1)
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("move_back"):
		step = Vector2i(0, 1)
	if step != Vector2i.ZERO:
		get_viewport().set_input_as_handled()
		move_sel(step)


## `mMP_move_Play`: one acre, if there is one that way.
func move_sel(step: Vector2i) -> void:
	var next := Vector2i(clampi(sel.x + step.x, 0, TownFieldGenerator.FG_X_NUM - 1),
		clampi(sel.y + step.y, 0, TownFieldGenerator.FG_Z_NUM - 1))
	if next == sel:
		return
	sel = next
	_cursor_target = Vector2(sel.x * BLOCK, -sel.y * BLOCK)
	Audio.play_se(&"cursol")


func _process(delta: float) -> void:
	_accum += delta * DecompTime.TICK_HZ
	var steps := 0
	while _accum >= 1.0 and steps < 8:
		_accum -= 1.0
		steps += 1
		_cursor_frame = (_cursor_frame + 1) % TownMap.CURSOR_FRAMES
		## `mMP_move_Wait`.
		_cursor.x = NoticeBoardOverlay.add_calc(_cursor.x, _cursor_target.x, 0.7, 19.0, 1.8).x
		_cursor.y = NoticeBoardOverlay.add_calc(_cursor.y, _cursor_target.y, 0.7, 19.0, 1.8).x
		if _cursor.distance_to(_cursor_target) < 0.1:
			_cursor = _cursor_target
	if steps > 0:
		_canvas.queue_redraw()


func _blocked_by_other_ui() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	for group: String in ["dialogue_ui", "shop_ui", "inventory_ui", "debug_console_ui"]:
		var node: Node = tree.get_first_node_in_group(group)
		if node != null and node.has_method("is_open") and bool(node.call("is_open")):
			return true
	return false


func _resolve_player_fg() -> Vector2i:
	var tree := get_tree()
	if tree == null:
		return Vector2i(2, 1)
	var player := Player.find(tree)
	if player == null or not (player is Node3D):
		return Vector2i(2, 1)
	var world := World.find(tree)
	var grid: WorldGrid = null
	if world != null and "grid" in world:
		grid = world.grid
	if grid == null:
		return Vector2i(2, 1)
	var block: Vector2i = VillagerWalk.block_from_cell(grid.world_to_cell((player as Node3D).global_position))
	var fg: Vector2i = TownMap.fg_from_block(block)
	return fg if fg.x >= 0 else Vector2i(2, 1)


static func to_screen(p: Vector2) -> Vector2:
	return Vector2(160.0 + p.x, 120.0 - p.y)


func _blit(name: String, bounds: Rect2, at: Vector2, scale_by: float = 1.0, tint: Color = Color.WHITE) -> void:
	var tex: Texture2D = _tex_of(name)
	if tex == null:
		return
	var top_left := to_screen(at) + Vector2(bounds.position.x, -bounds.position.y) * scale_by
	_canvas.draw_texture_rect(tex, Rect2(top_left, bounds.size * scale_by), false, tint)


func _draw_canvas() -> void:
	if not _root.visible:
		return
	_blit("mp_base%d" % color_set, SCREEN_BOUNDS, Vector2.ZERO)
	## `mMP_set_map_dl`.
	var grid_tl := to_screen(MAP_ORIGIN + Vector2(-BLOCK * 0.5, BLOCK * 0.5))
	var grid_size := Vector2(TownFieldGenerator.FG_X_NUM, TownFieldGenerator.FG_Z_NUM) * BLOCK
	if _atlas != null:
		_canvas.draw_texture_rect(_atlas, Rect2(grid_tl, grid_size), false)
	else:
		_canvas.draw_rect(Rect2(grid_tl, grid_size), Color(0.45, 0.75, 0.4))
	var entry: Dictionary = acres.get(sel, {})
	var count: int = mini(label_count(entry), 4)
	_blit("mp_win%d_%d" % [color_set, count], SCREEN_BOUNDS, Vector2.ZERO)
	_blit("mp_num%d" % (sel.x + 1), SCREEN_BOUNDS, Vector2.ZERO)
	_blit("mp_let%s" % LETTERS[clampi(sel.y, 0, 5)], SCREEN_BOUNDS, Vector2.ZERO)
	_draw_label_icons(entry)
	_draw_house_marks()
	## `mMP_set_cursol_dl`.
	var s: float = TownMap.cursor_scale(_cursor_frame)
	_blit("mp_cursor", MARK_BOUNDS, _cursor + MAP_ORIGIN, s, Color(1.0, TownMap.cursor_green(_cursor_frame), 1.0))
	_draw_text(entry)


## `mMP_set_label_top_dl`: the label's icon, once per resident for houses (12 apart).
func _draw_label_icons(entry: Dictionary) -> void:
	if entry.is_empty():
		return
	var label: int = int(entry["label"])
	var def: Array = LABELS[label]
	var at: Vector2 = def[1]
	var residents: Array = entry["residents"]
	var n: int = maxi(residents.size(), 1) if label == MapLabel.NPC or label == MapLabel.PLAYER else 1
	for i: int in n:
		var icon: String = def[0]
		if label == MapLabel.NPC and i < residents.size():
			icon = "npcT_%d" % (int(residents[i]["layer"]) + 1)
		_blit("mp_" + icon, MARK_BOUNDS, at + Vector2(0, -12.0 * i))


## `mMP_set_house_dl`: villager marks in every acre and "you are here".
func _draw_house_marks() -> void:
	for fg: Variant in acres.keys():
		var e: Dictionary = acres[fg]
		if int(e["label"]) != MapLabel.NPC:
			continue
		var f: Vector2i = fg
		var left: float = MAP_ORIGIN.x - BLOCK * 0.5 + f.x * BLOCK
		var top: float = MAP_ORIGIN.y + BLOCK * 0.5 - f.y * BLOCK
		for r: Dictionary in e["residents"]:
			var idx: int = int(r["idx"])
			_blit("mp_npc2T_%d" % (int(r["layer"]) + 1), MARK_BOUNDS,
				Vector2(left + HOUSE_OFS_X[idx % 3], top + HOUSE_OFS_Y[idx / 3]))
	var here := Vector2(MAP_ORIGIN.x - BLOCK * 0.5 + player_fg.x * BLOCK + 8.0,
		MAP_ORIGIN.y - BLOCK * 0.5 - player_fg.y * BLOCK + 9.0)
	_blit("mp_genzaiT", MARK_BOUNDS, here)


## The town name and `mMP_set_label_dl`'s words: resident names (squeezed to 54 wide)
## or the building's name.
func _draw_text(entry: Dictionary) -> void:
	if _font == null:
		return
	var name_pos := Vector2(-136.0 + 24.0 + 160.0, 120.0 - (102.0 - 29.0))
	_canvas.draw_string(_font, name_pos + Vector2(0, _font.get_ascent(FONT_PX)),
		Game.town_name if Game != null else "Town", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX, LAND_COLOR[color_set])
	if entry.is_empty():
		return
	var px := int(round(FONT_PX * 0.75))
	var asc := _font.get_ascent(px)
	var def: Array = LABELS[int(entry["label"])]
	for word: Array in def[2]:
		var at := Vector2(160.0 + float(word[1]), 120.0 - float(word[2]))
		if str(word[0]) != "":
			_canvas.draw_string(_font, at + Vector2(0, asc), str(word[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, px, WORD_COLOR)
			continue
		for r: Dictionary in entry["residents"]:
			var text: String = str(r["name"])
			var w: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX).x
			var sx: float = minf(0.75, 54.0 / maxf(w, 1.0))
			_canvas.draw_set_transform(at + Vector2(0, asc), 0.0, Vector2(sx / 0.75, 1.0))
			_canvas.draw_string(_font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px,
				FREE_COLOR if int(r["sex"]) == -1 else NAME_COLOR)
			_canvas.draw_set_transform(Vector2.ZERO)
			at.y += 12.0
