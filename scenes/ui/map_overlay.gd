extends CanvasLayer

## Town map submenu (`m_map_ovl`). Acre art from pipeline `kan_tizu_*` tiles.

const ROW_LETTERS := ["a", "b", "c", "d", "e", "f"]
## Villager-house offsets inside an acre (`mMP_set_house_dl` idx 0..3).
const _HOUSE_OFS := [
	Vector2(0.22, 0.28),
	Vector2(0.55, 0.28),
	Vector2(0.22, 0.58),
	Vector2(0.55, 0.58),
]

@onready var _root: Control = %Root
@onready var _paper: PanelContainer = %Paper
@onready var _shell: TextureRect = %WindowShell
@onready var _shell_stack: Control = %ShellStack
@onready var _town_name: Label = %TownName
@onready var _acre_letter: TextureRect = %AcreLetter
@onready var _acre_number: TextureRect = %AcreNumber
@onready var _acre_label: Label = %AcreLabel
@onready var _feature_icon: TextureRect = %FeatureIcon
@onready var _info_panel: TextureRect = %InfoPanel
@onready var _info_stack: Control = %InfoStack
@onready var _grid: Control = %AcreGrid
@onready var _map_image: TextureRect = %MapImage
@onready var _icon_layer: Control = %IconLayer
@onready var _cursor: TextureRect = %Cursor
@onready var _here: TextureRect = %HereMark
@onready var _hint: Label = %HintLabel

## Native `kan_win_kiwaku` outer AABB (GC units).
const _SHELL_NATIVE := Vector2(272, 204)
## Display scale for the yellow window shell (unchanged — grow the map inside it).
const _SHELL_DISPLAY_SCALE := 2.9
## Paper inset as a fraction of shell size.
const _SHELL_INSET_FRAC := 0.10
## Info bubble kept smaller so acre tiles can use the body.
const _INFO_TO_MAP_W := 0.58
const _INFO_TO_MAP_H := 0.70

var _open: bool = false
var _sel: Vector2i = Vector2i.ZERO
var _player_fg: Vector2i = Vector2i.ZERO
var _cursor_frame: int = 0
var _layout: WorldData = null


func _ready() -> void:
	layer = 21
	add_to_group("map_ui")
	_root.visible = false
	_size_grid()
	_apply_chrome()


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_layout = Game.resolve_world_data() if Game != null else null
	_player_fg = _resolve_player_fg()
	_sel = _player_fg if _player_fg.x >= 0 else Vector2i.ZERO
	_cursor_frame = 0
	_open = true
	_root.visible = true
	_refresh()


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("map"):
		if _blocked_by_other_ui():
			get_viewport().set_input_as_handled()
			return
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not _open:
		return
	if event.is_action_pressed("pause_menu") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("map"):
		close()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
		_move_sel(-1, 0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
		_move_sel(1, 0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("move_forward"):
		_move_sel(0, -1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("move_back"):
		_move_sel(0, 1)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not _open:
		return
	_cursor_frame = (_cursor_frame + 1) % TownMap.CURSOR_FRAMES
	_update_cursor_visual()


func _blocked_by_other_ui() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	for group: String in ["dialogue_ui", "shop_ui", "inventory_ui"]:
		var node: Node = tree.get_first_node_in_group(group)
		if node != null and node.has_method("is_open") and bool(node.call("is_open")):
			return true
	return false


func _size_grid() -> void:
	var cols: int = TownFieldGenerator.FG_X_NUM
	var rows: int = TownFieldGenerator.FG_Z_NUM
	var size := Vector2(float(cols * TownMap.TILE_PX), float(rows * TownMap.TILE_PX))
	_grid.custom_minimum_size = size
	if _map_image != null:
		_map_image.position = Vector2.ZERO
		_map_image.size = size
		_map_image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_map_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_map_image.stretch_mode = TextureRect.STRETCH_SCALE
	if _icon_layer != null:
		_icon_layer.position = Vector2.ZERO
		_icon_layer.size = size
	## Keep the acre bubble secondary so the map can use the window body.
	if _info_stack != null:
		_info_stack.custom_minimum_size = Vector2(
			size.x * _INFO_TO_MAP_W,
			size.y * _INFO_TO_MAP_H
		)


func _apply_chrome() -> void:
	var shell_tex: Texture2D = TownMap.load_chrome("window_shell")
	if shell_tex != null and _shell != null:
		_shell.texture = shell_tex
		_shell.visible = true
		_shell.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_layout_shell(shell_tex)
	if _paper != null:
		## Shell carries the yellow window; keep the panel transparent.
		_paper.self_modulate = Color(1, 1, 1, 0) if shell_tex != null else Color(0.96, 0.9, 0.78, 1)
	var map_tex: Texture2D = TownMap.load_chrome("map_label")
	var map_label: TextureRect = %MapLabel
	if map_tex != null and map_label != null:
		map_label.texture = map_tex
	var acre_tex: Texture2D = TownMap.load_chrome("acre_label")
	var acre_hdr: TextureRect = %AcreHeader
	if acre_tex != null and acre_hdr != null:
		acre_hdr.texture = acre_tex
	var info_tex: Texture2D = TownMap.load_chrome("info_panel")
	if info_tex != null and _info_panel != null:
		_info_panel.texture = info_tex
	var cursor_tex: Texture2D = TownMap.load_chrome("cursor_frame")
	if cursor_tex == null:
		cursor_tex = TownMap.load_chrome("cursor")
	if cursor_tex != null:
		_cursor.texture = cursor_tex
	var here_tex: Texture2D = TownMap.load_chrome("here_mark")
	if here_tex != null:
		_here.texture = here_tex
	_place_axis_labels()


func _layout_shell(shell_tex: Texture2D) -> void:
	if _shell_stack == null:
		return
	var native := _SHELL_NATIVE
	var size := native * _SHELL_DISPLAY_SCALE
	## Prefer baked aspect if the PNG differs slightly from the AABB.
	if shell_tex.get_width() > 0 and shell_tex.get_height() > 0:
		var aspect := float(shell_tex.get_width()) / float(shell_tex.get_height())
		size = Vector2(size.y * aspect, size.y)
	_shell_stack.custom_minimum_size = size
	if _paper == null:
		return
	var inset := mini(size.x, size.y) * _SHELL_INSET_FRAC
	_paper.offset_left = inset
	_paper.offset_top = inset
	_paper.offset_right = -inset
	_paper.offset_bottom = -inset


func _place_axis_labels() -> void:
	var col_row: HBoxContainer = %ColLabels
	var row_col: VBoxContainer = %RowLabels
	for child: Node in col_row.get_children():
		child.queue_free()
	for child: Node in row_col.get_children():
		child.queue_free()
	## Spacer so column digits align with the map (not the row letters).
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(24, 20)
	col_row.add_child(spacer)
	for i: int in TownFieldGenerator.FG_X_NUM:
		var tr := TextureRect.new()
		tr.custom_minimum_size = Vector2(TownMap.TILE_PX, 22)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.texture = TownMap.load_chrome("col_%d" % (i + 1))
		col_row.add_child(tr)
	for i: int in TownFieldGenerator.FG_Z_NUM:
		var tr := TextureRect.new()
		tr.custom_minimum_size = Vector2(24, TownMap.TILE_PX)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.texture = TownMap.load_chrome("row_%s" % ROW_LETTERS[i])
		row_col.add_child(tr)


func _resolve_player_fg() -> Vector2i:
	var tree := get_tree()
	if tree == null:
		return Vector2i.ZERO
	var player: Node = tree.get_first_node_in_group("player")
	if player == null or not (player is Node3D):
		return Vector2i.ZERO
	var world: Node = tree.get_first_node_in_group("world")
	var grid: WorldGrid = null
	if world != null and "grid" in world:
		grid = world.get("grid") as WorldGrid
	if grid == null:
		return Vector2i(2, 2)
	var block: Vector2i = VillagerWalk.block_from_cell(grid.world_to_cell((player as Node3D).global_position))
	var fg: Vector2i = TownMap.fg_from_block(block)
	if fg.x < 0:
		return Vector2i(2, 2)
	return fg


func _move_sel(dx: int, dy: int) -> void:
	_sel.x = clampi(_sel.x + dx, 0, TownFieldGenerator.FG_X_NUM - 1)
	_sel.y = clampi(_sel.y + dy, 0, TownFieldGenerator.FG_Z_NUM - 1)
	_refresh_selection()


func _refresh() -> void:
	if _town_name != null:
		_town_name.text = Game.town_name if Game != null else "Town"
	var types: PackedByteArray = TownMap.fg_acre_types(_layout)
	if _map_image != null:
		var atlas: Texture2D = TownMap.compose_fg_texture(types) if TownMap.assets_ready() else null
		_map_image.texture = atlas
		_map_image.modulate = Color.WHITE if atlas != null else Color(0.45, 0.75, 0.4, 1)
	_place_house_icons()
	_refresh_selection()
	_update_here_mark()
	if _hint != null:
		_hint.text = (
			""
			if TownMap.assets_ready()
			else "Run: python3 tools/build_assets.py --step convert --kind map-ui"
		)


func _refresh_selection() -> void:
	if _acre_letter != null:
		_acre_letter.texture = TownMap.load_chrome("row_%s" % ROW_LETTERS[_sel.y])
	if _acre_number != null:
		_acre_number.texture = TownMap.load_chrome("col_%d" % (_sel.x + 1))
	if _acre_label != null:
		_acre_label.text = TownMap.label_for_acre(_layout, _sel)
	if _feature_icon != null:
		var icon_name: String = TownMap.icon_name_for_acre(_layout, _sel)
		_feature_icon.texture = TownMap.load_chrome(icon_name) if not icon_name.is_empty() else null
		_feature_icon.visible = _feature_icon.texture != null
	_update_cursor_visual()


func _place_house_icons() -> void:
	if _icon_layer == null:
		return
	for child: Node in _icon_layer.get_children():
		child.queue_free()
	if _layout == null:
		return
	var house_tex: Texture2D = TownMap.load_chrome("icon_house")
	if house_tex == null:
		return
	## Group villager / player houses by FG acre.
	var by_fg: Dictionary = {}
	for b: BuildingPlacement in _layout.buildings:
		if b == null:
			continue
		var id := String(b.id)
		if not (id.begins_with("npc_house_") or id == "player_house"):
			continue
		var fg: Vector2i = TownMap.fg_from_block(VillagerWalk.block_from_cell(b.cell))
		if fg.x < 0:
			continue
		if not by_fg.has(fg):
			by_fg[fg] = 0
		var idx: int = int(by_fg[fg])
		by_fg[fg] = idx + 1
		if idx >= _HOUSE_OFS.size():
			continue
		var tr := TextureRect.new()
		tr.texture = house_tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon_px := float(TownMap.TILE_PX) * 0.38
		tr.size = Vector2(icon_px, icon_px)
		var ofs: Vector2 = _HOUSE_OFS[idx]
		tr.position = Vector2(
			float(_sel_x_px(fg.x)) + ofs.x * float(TownMap.TILE_PX),
			float(_sel_y_px(fg.y)) + ofs.y * float(TownMap.TILE_PX)
		)
		## Player house uses a warmer tint; villagers stay pipeline purple.
		if id == "player_house":
			tr.modulate = Color(0.95, 0.55, 0.2, 1)
		_icon_layer.add_child(tr)


func _sel_x_px(fx: int) -> int:
	return fx * TownMap.TILE_PX


func _sel_y_px(fy: int) -> int:
	return fy * TownMap.TILE_PX


func _update_cursor_visual() -> void:
	if _cursor == null:
		return
	var g: float = TownMap.cursor_green(_cursor_frame)
	var s: float = TownMap.cursor_scale(_cursor_frame)
	_cursor.modulate = Color(1.0, g, 1.0, 1.0)
	var base := float(TownMap.TILE_PX)
	var size := base * s
	_cursor.size = Vector2(size, size)
	_cursor.position = Vector2(
		float(_sel.x) * base + (base - size) * 0.5,
		float(_sel.y) * base + (base - size) * 0.5
	)


func _update_here_mark() -> void:
	if _here == null:
		return
	_here.visible = _player_fg.x >= 0
	if not _here.visible:
		return
	var mark := float(TownMap.TILE_PX) * 0.42
	_here.size = Vector2(mark, mark)
	_here.position = Vector2(
		float(_player_fg.x) * TownMap.TILE_PX + float(TownMap.TILE_PX) * 0.48,
		float(_player_fg.y) * TownMap.TILE_PX + float(TownMap.TILE_PX) * 0.12
	)
