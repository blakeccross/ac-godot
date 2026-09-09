class_name DesignPattern
extends RefCounted

## One 32x32, 16-colour original design (`mNW_original_design_c`,
## `include/m_needlework.h:58-63`).
##
## Decomp stores the texture as a 512-byte CI4 blob with GameCube 8x8-tile swizzle
## (`mDE_POS2TEXEL`). Here it is kept unswizzled row-major (`pixels[y*32 + x]`, one
## index 0-15 per texel) for cheap editing / rendering; `to_ci4()` / `from_ci4()`
## convert to and from the decomp layout for ROM blobs and the GBA transfer path.

const WIDTH := 32
const HEIGHT := 32
const NAME_LEN := 16
const CI4_SIZE := 512  ## mNW_DESIGN_TEX_SIZE
const BLANK_INDEX := 0xF  ## mNW_InitOriginalData fills every texel with 0xF

var name: String = "blank"
var palette: int = 0  ## 0-15, index into NeedleworkPalettes
var flag_set: bool = false  ## flag_design_set
var pixels: PackedByteArray = _blank_pixels()


static func _blank_pixels() -> PackedByteArray:
	var p := PackedByteArray()
	p.resize(WIDTH * HEIGHT)
	p.fill(BLANK_INDEX)
	return p


## A fresh blank design (`mNW_InitOriginalData`).
static func blank() -> DesignPattern:
	var d := DesignPattern.new()
	d.name = "blank"
	d.palette = 0
	d.flag_set = false
	d.pixels = _blank_pixels()
	return d


func duplicate_design() -> DesignPattern:
	var d := DesignPattern.new()
	d.name = name
	d.palette = palette
	d.flag_set = flag_set
	d.pixels = pixels.duplicate()
	return d


## Overwrite this design's contents from another (`mNW_CopyOriginalTextureClass`).
func copy_from(src: DesignPattern) -> void:
	name = src.name
	palette = src.palette
	flag_set = src.flag_set
	pixels = src.pixels.duplicate()


func get_px(x: int, y: int) -> int:
	if x < 0 or x >= WIDTH or y < 0 or y >= HEIGHT:
		return 0
	return pixels[y * WIDTH + x]


func set_px(x: int, y: int, ci: int) -> void:
	if x < 0 or x >= WIDTH or y < 0 or y >= HEIGHT:
		return
	pixels[y * WIDTH + x] = ci & 0xF


func clamp_name() -> void:
	if name.length() > NAME_LEN:
		name = name.substr(0, NAME_LEN)


# --- procedural motifs (placeholder art until ARAM slots 27/28 are extracted) --

enum Motif { SOLID, VSTRIPE, HSTRIPE, CHECK, GRID, POLKA, DIAGONAL, DIAMOND, FLOWER, PLAID }


## A simple 32x32 pattern in indices `fg` / `bg` (0-15). `fg`/`bg` are palette CI
## indices, not colours — the rendered look follows whatever `palette` is set.
static func generate(motif: Motif, palette: int, fg: int = 2, bg: int = 9) -> DesignPattern:
	var d := DesignPattern.new()
	d.palette = palette & 0xF
	d.flag_set = true
	var px := PackedByteArray()
	px.resize(WIDTH * HEIGHT)
	for y in HEIGHT:
		for x in WIDTH:
			px[y * WIDTH + x] = _motif_px(motif, x, y, fg, bg)
	d.pixels = px
	return d


static func _motif_px(motif: int, x: int, y: int, fg: int, bg: int) -> int:
	match motif:
		Motif.SOLID:
			return fg
		Motif.VSTRIPE:
			return fg if (x / 4) % 2 == 0 else bg
		Motif.HSTRIPE:
			return fg if (y / 4) % 2 == 0 else bg
		Motif.CHECK:
			return fg if ((x / 4) + (y / 4)) % 2 == 0 else bg
		Motif.GRID:
			return fg if (x % 8 == 0 or y % 8 == 0) else bg
		Motif.POLKA:
			var cx: int = x % 8 - 4
			var cy: int = y % 8 - 4
			return fg if (cx * cx + cy * cy) <= 4 else bg
		Motif.DIAGONAL:
			return fg if ((x + y) / 3) % 2 == 0 else bg
		Motif.DIAMOND:
			var dx: int = absi(x % 8 - 4)
			var dy: int = absi(y % 8 - 4)
			return fg if (dx + dy) <= 3 else bg
		Motif.FLOWER:
			var mx: float = float(x) - 15.5
			var my: float = float(y) - 15.5
			var r: float = sqrt(mx * mx + my * my)
			var a: float = atan2(my, mx)
			if r < 3.0:
				return fg
			if r < 12.0 and cos(a * 5.0) > 0.2:
				return fg
			return bg
		Motif.PLAID:
			var v: bool = (x % 8 < 3)
			var h: bool = (y % 8 < 3)
			if v and h:
				return fg
			if v or h:
				return (fg + bg) / 2
			return bg
	return bg


# --- decomp CI4 tile-swizzle (mDE_POS2TEXEL) ------------------------------------

static func _texel_byte(x: int, y: int) -> int:
	var within: int = (x & 7) + (y & 7) * 8
	var tile: int = ((x & 0x18) >> 3) + (((y & 0x18) >> 3) * 4)
	return (within + tile * 0x40) >> 1


## Row-major indices -> 512-byte CI4 blob in GameCube tile order.
func to_ci4() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(CI4_SIZE)
	out.fill(0)
	for y in HEIGHT:
		for x in WIDTH:
			var b: int = _texel_byte(x, y)
			var ci: int = pixels[y * WIDTH + x] & 0xF
			if (x & 1) == 0:
				out[b] = (out[b] & 0x0F) | (ci << 4)
			else:
				out[b] = (out[b] & 0xF0) | ci
	return out


func from_ci4(blob: PackedByteArray) -> void:
	if blob.size() < CI4_SIZE:
		return
	var p := PackedByteArray()
	p.resize(WIDTH * HEIGHT)
	for y in HEIGHT:
		for x in WIDTH:
			var b: int = _texel_byte(x, y)
			var byte: int = blob[b]
			p[y * WIDTH + x] = (byte >> 4) if (x & 1) == 0 else (byte & 0xF)
	pixels = p


## Nibble-swap every byte of the CI4 blob (`mNW_GC_to_Agb_texture` /
## `mNW_AGB_to_GC_texture`). Used only by the GBA transfer path.
static func agb_swap(blob: PackedByteArray) -> PackedByteArray:
	var out := blob.duplicate()
	for i in out.size():
		var v: int = out[i]
		out[i] = ((v << 4) | (v >> 4)) & 0xFF
	return out


# --- persistence --------------------------------------------------------------

func to_save() -> Dictionary:
	return {
		"name": name,
		"palette": palette,
		"flag": flag_set,
		"px": Marshalls.raw_to_base64(pixels),
	}


static func from_save(data: Variant) -> DesignPattern:
	var d := DesignPattern.blank()
	if typeof(data) != TYPE_DICTIONARY:
		return d
	var dict: Dictionary = data
	d.name = str(dict.get("name", "blank"))
	d.palette = int(dict.get("palette", 0)) & 0xF
	d.flag_set = bool(dict.get("flag", false))
	var raw: String = str(dict.get("px", ""))
	if not raw.is_empty():
		var bytes: PackedByteArray = Marshalls.base64_to_raw(raw)
		if bytes.size() == WIDTH * HEIGHT:
			d.pixels = bytes
	return d
