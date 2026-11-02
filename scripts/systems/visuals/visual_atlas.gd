class_name VisualAtlas
extends RefCounted
## Wrap-baked atlas helpers. The pipeline expands a bank tile into an atlas and remaps
## UVs to 0–1, so swapping a texture (season pack, room wallpaper, shirt) means
## re-tiling the new tile to the atlas size and cell period of the material it replaces.
##
## A town places hundreds of trees that all swap the same season sheet onto the same
## atlas size. Building a fresh image for each one copies a 512² RGBA texture (1 MB,
## and again on the GPU) per surface, which is what pushed the phone over its memory
## limit on save and on the next launch. One sheet is kept per source and target.

## `(source, target, mirror, cell)` → the re-tiled sheet.
static var _tile_cache: Dictionary = {}
## `(source, fallback)` → wrap period, so the pixel scan runs once per atlas.
static var _period_cache: Dictionary = {}


static func albedo_size(mat: StandardMaterial3D) -> Vector2i:
	if mat == null or mat.albedo_texture == null:
		return Vector2i.ZERO
	var tex: Texture2D = mat.albedo_texture
	return Vector2i(tex.get_width(), tex.get_height())


static func texture_image(tex: Texture2D) -> Image:
	if tex == null:
		return null
	var img: Image = tex.get_image()
	if img == null and not tex.resource_path.is_empty():
		img = Image.load_from_file(ProjectSettings.globalize_path(tex.resource_path))
	if img == null:
		return null
	if img.is_compressed():
		img = img.duplicate()
		if img.decompress() != OK:
			return null
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


static func tile_to_atlas(
	tile: Texture2D,
	target: Vector2i,
	mirror_u: bool = false,
	mirror_v: bool = false,
	tile_size: int = 0
) -> Texture2D:
	## Pipeline wrap-bake expands a bank tile into an atlas and remaps UVs to 0–1.
	## Swapping a single tile without re-tiling makes wallpapers look glitchy.
	## Room floors are GX_MIRROR (odd cells flipped) so a corner tile becomes one medallion.
	if tile == null:
		return null
	if target.x <= 0 or target.y <= 0:
		return tile
	var key := _tile_key(tile, target, mirror_u, mirror_v, tile_size)
	var cached: Variant = _tile_cache.get(key)
	if cached is Texture2D:
		return cached as Texture2D
	## Already the right sheet: share it. Copying here was one image per tree.
	if (
		not mirror_u
		and not mirror_v
		and tile.get_width() == target.x
		and tile.get_height() == target.y
		and (tile_size <= 0 or (tile.get_width() == tile_size and tile.get_height() == tile_size))
	):
		_tile_cache[key] = tile
		return tile
	var src: Image = texture_image(tile)
	if src == null:
		return tile
	## Bank pages are 64×64. Field capped ACHD tiles are 128²; tree leaf/trunk may
	## be full ACHD (512²). Only shrink when the season sheet is not an exact
	## atlas cell (room wallpaper HD / stale pack mismatch).
	const BANK_TILE := 64
	var cell: int = tile_size
	if cell <= 0:
		var sw: int = src.get_width()
		var sh: int = src.get_height()
		var exact_cell := (
			sw > 0
			and sh > 0
			and target.x % sw == 0
			and target.y % sh == 0
		)
		if (
			not exact_cell
			and sw == sh
			and sw > BANK_TILE
			and (mirror_u or mirror_v or target.x < sw or target.y < sh)
		):
			cell = BANK_TILE
		else:
			cell = 0
	if cell > 0 and (src.get_width() != cell or src.get_height() != cell):
		src = src.duplicate()
		src.resize(cell, cell, Image.INTERPOLATE_NEAREST)
	var tw: int = src.get_width()
	var th: int = src.get_height()
	if tw <= 0 or th <= 0:
		_tile_cache[key] = tile
		return tile
	if tw == target.x and th == target.y and not mirror_u and not mirror_v:
		var same := ImageTexture.create_from_image(src)
		_tile_cache[key] = same
		return same
	var out := Image.create(target.x, target.y, false, Image.FORMAT_RGBA8)
	var tiles_u: int = maxi(1, int(ceili(float(target.x) / float(tw))))
	var tiles_v: int = maxi(1, int(ceili(float(target.y) / float(th))))
	for tj: int in tiles_v:
		for ti: int in tiles_u:
			var patch: Image = src
			var flip_u := mirror_u and (ti & 1) == 1
			var flip_v := mirror_v and (tj & 1) == 1
			if flip_u or flip_v:
				patch = src.duplicate()
				if flip_u:
					patch.flip_x()
				if flip_v:
					patch.flip_y()
			out.blit_rect(patch, Rect2i(0, 0, tw, th), Vector2i(ti * tw, tj * th))
	if out.get_width() != target.x or out.get_height() != target.y:
		out = out.get_region(Rect2i(0, 0, target.x, target.y))
	var made := ImageTexture.create_from_image(out)
	_tile_cache[key] = made
	return made


static func infer_tile_size(atlas: Texture2D, fallback: int = 64) -> int:
	## Smallest period that tiles the wrap-bake atlas (shop wall DMA is 64²).
	if atlas == null:
		return fallback
	var period_key := "%s|%d" % [_source_id(atlas), fallback]
	if _period_cache.has(period_key):
		return int(_period_cache[period_key])
	var img: Image = texture_image(atlas)
	var found: int = fallback
	if img != null:
		var w: int = img.get_width()
		var h: int = img.get_height()
		## Prefer the smallest period that actually repeats (≥2 cells on an axis).
		for period: int in [32, 64, 128, 256]:
			if period > mini(w, h):
				continue
			if w % period != 0 or h % period != 0:
				continue
			if w < period * 2 and h < period * 2:
				continue
			if _image_has_period(img, period):
				found = period
				break
	_period_cache[period_key] = found
	return found


static func _source_id(tex: Texture2D) -> String:
	return tex.resource_path if tex.resource_path != "" else str(tex.get_instance_id())


static func _tile_key(
	tile: Texture2D, target: Vector2i, mirror_u: bool, mirror_v: bool, tile_size: int
) -> String:
	return "%s|%d|%d|%d|%d|%d" % [
		_source_id(tile), target.x, target.y, int(mirror_u), int(mirror_v), tile_size,
	]


static func _image_has_period(img: Image, period: int) -> bool:
	var w: int = img.get_width()
	var h: int = img.get_height()
	if period <= 0 or w % period != 0 or h % period != 0:
		return false
	## Sample a sparse grid — full compare is expensive on large atlases.
	if w >= period * 2:
		@warning_ignore("integer_division")
		for y: int in range(0, h, maxi(period / 8, 1)):
			@warning_ignore("integer_division")
			for x: int in range(0, w - period, maxi(period / 8, 1)):
				if img.get_pixel(x, y) != img.get_pixel(x + period, y):
					return false
	if h >= period * 2:
		@warning_ignore("integer_division")
		for x: int in range(0, w, maxi(period / 8, 1)):
			@warning_ignore("integer_division")
			for y: int in range(0, h - period, maxi(period / 8, 1)):
				if img.get_pixel(x, y) != img.get_pixel(x, y + period):
					return false
	return w >= period * 2 or h >= period * 2
