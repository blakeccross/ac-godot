class_name InteriorShadow
extends RefCounted

## Soft elliptical drop shadow under an interior fixture / NPC (the AC:GC
## `ACTOR_SHADOW` role). A flat unshaded MUL-blended quad with a radial falloff —
## reliable indoors, where the outdoor `actor_blob_shadow` heightfield probe has
## nothing to sit on.

static var _tex: ImageTexture = null


## MUL blend: white (×1, no change) at the rim → dark grey at the centre.
static func _texture() -> ImageTexture:
	if _tex == null:
		var n := 96
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		var c := (n - 1) * 0.5
		for y in n:
			for x in n:
				var d: float = Vector2(x - c, y - c).length() / c  ## 0 centre → 1 edge
				var g: float = lerpf(0.4, 1.0, smoothstep(0.15, 1.0, d))
				img.set_pixel(x, y, Color(g, g, g * 1.03, 1.0))
		_tex = ImageTexture.create_from_image(img)
	return _tex


## Add a `BlobShadow` MeshInstance3D under `host` (idempotent). `alpha` deepens it
## (~0.34 for props, ~0.4 for NPCs).
static func add(host: Node3D, extent: Vector2, alpha: float = 0.4) -> void:
	if host == null or host.get_node_or_null("BlobShadow") != null:
		return
	var blob := MeshInstance3D.new()
	blob.name = "BlobShadow"
	var plane := PlaneMesh.new()  ## flat in XZ, normal +Y
	plane.size = extent * 2.0
	blob.mesh = plane
	blob.position = Vector3(0.0, 0.06, 0.0)
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	var tint: float = clampf(1.0 - (alpha - 0.34) * 0.9, 0.7, 1.0)
	mat.albedo_color = Color(tint, tint, tint, 1.0)
	mat.albedo_texture = _texture()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	blob.material_override = mat
	host.add_child(blob)
