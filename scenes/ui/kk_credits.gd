extends CanvasLayer

## The staff roll over K.K.'s song (`aMKBC_clip_roll_draw`): 16 pages of the disc's credit
## strings (`mString_MIKANBOX_START` 0x77B…), up to ten lines each, white, fading in over
## frames 40–120 of a page and out over its last 80. Section heads (`index_line_table`) are
## drawn smaller.

const STRING_FIRST := 0x77B
const STRING_LAST := 0x7FE
## `page_table`: first line of each page (the 17th entry closes page 16).
const PAGE_TABLE: Array[int] = [0, 9, 18, 27, 37, 45, 53, 57, 66, 74, 82, 89, 96, 103, 112, 122, 124]
const INDEX_LINES: Array[int] = [
	3, 6, 9, 12, 16, 18, 21, 25, 27, 30, 37, 40, 43, 45, 48, 51,
	53, 57, 60, 66, 74, 82, 86, 89, 91, 96, 100, 103, 112, 116, 119, 122,
]
const PAGE_FRAMES := 446.0

@onready var _lines: VBoxContainer = $Lines

var _page: int = -2


func show_page(page: int, frame: float) -> void:
	if page != _page:
		_page = page
		_fill(page)
	var alpha: float = 0.0
	if frame < 40.0 or frame > PAGE_FRAMES:
		alpha = 0.0
	elif frame < 120.0:
		alpha = (frame - 40.0) / 80.0
	elif frame > PAGE_FRAMES - 80.0:
		alpha = (PAGE_FRAMES - frame) / 80.0
	else:
		alpha = 1.0
	_lines.modulate.a = clampf(alpha, 0.0, 1.0) if page >= 0 else 0.0


func _fill(page: int) -> void:
	for child: Node in _lines.get_children():
		child.queue_free()
	if page < 0 or page >= PAGE_TABLE.size() - 1:
		return
	for j: int in range(PAGE_TABLE[page], PAGE_TABLE[page + 1]):
		var label := Label.new()
		var id: int = mini(STRING_FIRST + j, STRING_LAST)
		label.text = DialogueCatalog.rom_string(id)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
		var size: int = 22
		if j in INDEX_LINES:
			size = 18
		label.add_theme_font_size_override("font_size", size)
		_lines.add_child(label)
