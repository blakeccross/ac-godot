shader_type spatial;
// The fireplace's flame (`int_ike_kama_danrofire_off_model`, `fIKD_dw`): two I4 tiles, colour
// `(PRIM - ENV) * I0 + ENV` then times PRIM, alpha `I1 * PRIM_LOD_FRAC`. Tile 1 is scrolled up
// the card a texel per game frame (`two_tex_scroll_dolphin(..., 0, -ctr << 2, 32, 64)`).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// Intensity lives in alpha (RGB is white): `i4_png_as_alpha`.
uniform sampler2D tile0 : hint_default_black, filter_nearest, repeat_enable;
uniform sampler2D tile1 : hint_default_black, filter_nearest, repeat_enable;
uniform vec3 prim_color : source_color = vec3(1.0, 1.0, 0.588);
uniform vec3 env_color : source_color = vec3(1.0, 0.0, 0.0);
uniform float lod_frac = 0.529;
// UV (tile 1 space) per second: a texel per 60 Hz game frame over the tile's height.
uniform float scroll_per_sec = 0.9375;

void fragment() {
	vec2 size0 = vec2(textureSize(tile0, 0));
	vec2 size1 = vec2(textureSize(tile1, 0));
	// Vertex UVs are tile 0's; tile 1 is a different size.
	vec2 uv1 = UV * size0 / size1;
	uv1.y += scroll_per_sec * TIME;
	float i0 = texture(tile0, UV).a;
	float i1 = texture(tile1, uv1).a;
	ALBEDO = mix(env_color, prim_color, i0) * prim_color;
	ALPHA = clamp(i1 * lod_frac, 0.0, 1.0);
}
