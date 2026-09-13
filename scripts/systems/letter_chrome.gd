class_name LetterChrome
extends RefCounted

## Stationery art + ink color for the "Read a letter" board overlay (`m_board_ovl.c`).
## Paper art is baked per design by `scenes/dev/letter_paper_bake.gd` (orthographic
## render of the already-converted `lat_letterNN.glb` models — see that script for why
## a render is used instead of grabbing a texture by name/size) into
## `assets/generated/ui/letter/paper{01..64}.png`. Ink colors are `letter_color[]`
## transcribed verbatim from `m_board_ovl.c:643-708` — used only for header/body/footer
## text color, never to tint the paper (`m_board_ovl.c:1220-1235`).

const PAPER_DIR := "res://assets/generated/ui/letter"
const PAPER_COUNT := 64

## `letter_color[PAPER_NUM]`, `m_board_ovl.c:643-708` (first 64 entries; the rest of the
## 256-length ROM array is unused padding, see `PAPER_UNIQUE_NUM`, `m_name_table.h:180`).
const _INK_255 := [
	[70, 40, 50], [40, 40, 130], [90, 30, 30], [75, 115, 215],
	[90, 70, 20], [110, 60, 0], [95, 25, 0], [255, 255, 255],
	[0, 100, 120], [40, 85, 0], [0, 40, 135], [155, 50, 60],
	[255, 255, 255], [255, 255, 255], [90, 90, 90], [0, 10, 130],
	[200, 255, 235], [70, 45, 30], [105, 65, 160], [65, 60, 0],
	[60, 0, 90], [85, 85, 85], [255, 180, 0], [85, 55, 0],
	[95, 75, 10], [120, 120, 120], [255, 255, 105], [109, 83, 21],
	[0, 155, 0], [100, 130, 185], [0, 100, 0], [90, 100, 0],
	[160, 0, 0], [115, 60, 0], [255, 185, 0], [255, 255, 205],
	[0, 0, 100], [0, 100, 155], [0, 100, 205], [165, 20, 0],
	[155, 40, 40], [0, 80, 135], [0, 20, 90], [100, 100, 155],
	[0, 80, 5], [95, 70, 0], [100, 140, 100], [255, 255, 255],
	[100, 110, 100], [80, 70, 0], [50, 155, 0], [0, 95, 175],
	[0, 50, 90], [0, 60, 205], [0, 100, 0], [0, 80, 80],
	[0, 115, 60], [100, 80, 100], [255, 255, 200], [90, 60, 0],
	[55, 125, 0], [0, 155, 0], [70, 50, 235], [255, 255, 255],
]

static var _tex_cache: Dictionary = {}


static func clamp_paper_type(paper_type: int) -> int:
	return clampi(paper_type, 0, PAPER_COUNT - 1)


static func ink_color(paper_type: int) -> Color:
	var rgb: Array = _INK_255[clamp_paper_type(paper_type)]
	return Color(rgb[0] / 255.0, rgb[1] / 255.0, rgb[2] / 255.0, 1.0)


static func paper_texture(paper_type: int) -> Texture2D:
	var idx: int = clamp_paper_type(paper_type)
	if _tex_cache.has(idx):
		return _tex_cache[idx] as Texture2D
	var path: String = "%s/paper%02d.png" % [PAPER_DIR, idx + 1]
	var tex: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_tex_cache[idx] = tex
	return tex
