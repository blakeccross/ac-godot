class_name InventoryCollectPage
extends Control
## One encyclopedia page (`inv_sakana_model` / `inv_mushi_model`, `m_inventory_ovl.c`): the
## shared shell with its own paper, rim and 8 x 5 ring grid, a title ribbon, and the page's tab
## on the right edge. A page that isn't up draws only its tab (`inv_*_part_model`).

signal tab_input(event: InputEvent)

## `SpeciesLog` kind of the page's grid.
@export var species_kind: StringName = &"fish"
## Suffix of the baked chrome: `page_shell_*`, `page_overlay_*`, `page_title_*`, `page_tab_*`.
@export var chrome_suffix: String = "fish"
## Baked paper this page scrolls (`inv_*_scroll_mode`).
@export var paper_stem: String = "fish_paper"
## The tab's quad in screen units about the page centre, y down (batch 14 of the model).
@export var tab_units: Rect2 = Rect2(94.0, -66.0, 30.0, 60.0)

## The screen the pockets window is authored on, in units (`_NATIVE_W` x `_NATIVE_H`).
const PAGE_UNITS := Vector2(240.0, 180.0)
## `mTG_collect_col_pos` / `mTG_collect_line_pos` for the 8 x 5 cells; y is up.
const COLS: Array[float] = [-89.0, -65.0, -41.0, -17.0, 8.0, 32.0, 57.0, 81.0]
const ROWS: Array[float] = [42.0, 18.0, -6.0, -30.0, -54.0]
const ICON_UNITS := 20.0

var _cells: Array[TextureRect] = []

@onready var _shadow: TextureRect = %Shadow
@onready var _shell: TextureRect = %Shell
@onready var _overlay: TextureRect = %Overlay
@onready var _title: TextureRect = %Title
@onready var _grid: Control = %Grid
@onready var _tab: TextureRect = %Tab


func _ready() -> void:
	var shell_tex: Texture2D = InventoryChrome.load_tex("page_shell_" + chrome_suffix)
	_shadow.texture = shell_tex
	_shell.texture = shell_tex
	var paper := _shell.material as ShaderMaterial
	if paper != null:
		paper.set_shader_parameter("paper_tex", InventoryChrome.load_tex(paper_stem))
	_overlay.texture = InventoryChrome.load_tex("page_overlay_" + chrome_suffix)
	_title.texture = InventoryChrome.load_tex("page_title_" + chrome_suffix)
	_tab.texture = InventoryChrome.load_tex("page_tab_" + chrome_suffix)
	_place(_tab, tab_units)
	_tab.gui_input.connect(tab_input.emit)
	for i: int in EncyclopediaCatalog.COLLECT_NUM:
		var cell := TextureRect.new()
		cell.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		cell.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cell.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.visible = false
		_place(cell, Rect2(
			Vector2(COLS[i % 8], -ROWS[i / 8]) - Vector2.ONE * ICON_UNITS * 0.5,
			Vector2.ONE * ICON_UNITS
		))
		_grid.add_child(cell)
		_cells.append(cell)


## Up: the whole page. Not up: just the tab (`inv_*_part_model`).
func set_full(on: bool) -> void:
	for node: CanvasItem in [_shadow, _shell, _overlay, _title, _grid]:
		node.visible = on


## Caught species show their card in the ring; the rest are just the empty ring.
func populate(book: SpeciesLog) -> void:
	for slot: int in _cells.size():
		var id: StringName = EncyclopediaCatalog.id_for(species_kind, slot)
		var caught: bool = book != null and book.has(id)
		var cell: TextureRect = _cells[slot]
		cell.visible = caught
		if caught:
			cell.texture = InventoryChrome.load_tex(EncyclopediaCatalog.icon_for(species_kind, slot))


## Anchor `node` to a rect in screen units about the page centre (y down), so it holds
## its place at any window scale.
func _place(node: Control, units: Rect2) -> void:
	var to_fraction := Vector2.ONE / PAGE_UNITS
	var top_left: Vector2 = (units.position + PAGE_UNITS * 0.5) * to_fraction
	var bottom_right: Vector2 = (units.end + PAGE_UNITS * 0.5) * to_fraction
	node.set_anchor(SIDE_LEFT, top_left.x)
	node.set_anchor(SIDE_TOP, top_left.y)
	node.set_anchor(SIDE_RIGHT, bottom_right.x)
	node.set_anchor(SIDE_BOTTOM, bottom_right.y)
	node.offset_left = 0.0
	node.offset_top = 0.0
	node.offset_right = 0.0
	node.offset_bottom = 0.0
