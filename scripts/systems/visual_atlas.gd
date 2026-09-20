class_name VisualAtlas
extends RefCounted
## Wrap-baked atlas helpers. The pipeline expands a bank tile into an atlas and remaps
## UVs to 0–1, so swapping a texture (season pack, room wallpaper, shirt) means
## re-tiling the new tile to the atlas size and cell period of the material it replaces.


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
		return tile
	if tw == target.x and th == target.y and not mirror_u and not mirror_v:
		return ImageTexture.create_from_image(src)
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
	return ImageTexture.create_from_image(out)


static func infer_tile_size(atlas: Texture2D, fallback: int = 64) -> int:
	## Smallest period that tiles the wrap-bake atlas (shop wall DMA is 64²).
	var img: Image = texture_image(atlas)
	if img == null:
		return fallback
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
			return period
	return fallback


static func _image_has_period(img: Image, period: int) -> bool:
	var w: int = img.get_width()
	var h: int = img.get_height()
	if period <= 0 or w % period != 0 or h % period != 0:
		return false
	## Sample a sparse grid — full compare is expensive on large atlases.
	if w >= period * 2:
		for y: int in range(0, h, maxi(period / 8, 1)):
			for x: int in range(0, w - period, maxi(period / 8, 1)):
				if img.get_pixel(x, y) != img.get_pixel(x + period, y):
					return false
	if h >= period * 2:
		for x: int in range(0, w, maxi(period / 8, 1)):
			for y: int in range(0, h - period, maxi(period / 8, 1)):
				if img.get_pixel(x, y) != img.get_pixel(x, y + period):
					return false
	return w >= period * 2 or h >= period * 2
