shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

// `obj_fallS_rainbowT_model` (`ac_fallS_draw.c_inc`). Two-cycle combine: colour = the
// RGBA16 bands (tile 0, 16x8, clamped), alpha = PRIM.a (120) x ENV.a (the rainbow's
// opacity) x the I4 fade mask (tile 1, 16x16, mirrored in t). The mesh UVs span the
// arc 0-1 (s 0-16, t 0-32 texels).

uniform sampler2D color_tex : source_color, filter_linear, repeat_disable;
uniform sampler2D mask_tex : filter_linear;
uniform float opacity = 0.0;

void fragment() {
	vec3 bands = texture(color_tex, vec2(UV.x, clamp(UV.y * 4.0, 0.0, 1.0))).rgb;
	float t = UV.y * 2.0;
	float mirrored = 1.0 - abs(mod(t, 2.0) - 1.0);
	float mask = texture(mask_tex, vec2(UV.x, mirrored)).r;
	ALBEDO = bands;
	ALPHA = (120.0 / 255.0) * opacity * mask;
}
