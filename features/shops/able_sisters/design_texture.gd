class_name DesignTexture
extends RefCounted

## Renders a `DesignPattern` (32x32 CI4 + preset palette) to an RGBA8 `ImageTexture`
## for use on cloth / mannequin / umbrella meshes and in the design UI.
## Cached by (pixels, palette) so repeated binds are cheap.

static var _cache: Dictionary = {}


static func build(d: DesignPattern) -> ImageTexture:
	if d == null:
		return null
	var key: int = hash([d.pixels, d.palette])
	var hit: Variant = _cache.get(key)
	if hit is ImageTexture:
		return hit
	var tex := ImageTexture.create_from_image(image(d))
	_cache[key] = tex
	return tex


static func image(d: DesignPattern) -> Image:
	var img := Image.create(DesignPattern.WIDTH, DesignPattern.HEIGHT, false, Image.FORMAT_RGBA8)
	var pal := NeedleworkPalettes.colors(d.palette)
	for y in DesignPattern.HEIGHT:
		for x in DesignPattern.WIDTH:
			img.set_pixel(x, y, pal[d.pixels[y * DesignPattern.WIDTH + x] & 0xF])
	return img


static func clear_cache() -> void:
	_cache.clear()
