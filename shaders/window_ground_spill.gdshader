shader_type spatial;
// XLU ground spill (`*_window_model` / `G_RM_AA_ZB_XLU_DECAL2` on SHADOW_DISP).
// Combiner: RGB = PRIMITIVE, A = TEXEL0 × PRIM_LOD_FRAC (120 when lights are on).
//
// RDP blends that alpha in 8-bit gamma space. Godot's blend_mix runs in the linear
// HDR buffer, so the same yellow × ~0.47 over night grass reads as opaque paint.
// Sample the backdrop, lerp in sRGB, then emit opaque ALBEDO (same fix as water).
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled,
		specular_disabled, ambient_light_disabled, fog_disabled;

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 0.588, 0.47);
// I4 coverage lives in PNG alpha. Linear filter matches m_rcp G_TF_BILERP on a
// 16×16 tile stretched over the fan — nearest makes a hard yellow slab.
uniform sampler2D albedo_texture : source_color, filter_linear, repeat_disable;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
// 1 GX above the acre so the fan is not coplanar with grass.
uniform float ground_lift = 0.05;

vec3 srgb_to_linear(vec3 c) {
	bvec3 cutoff = lessThanEqual(c, vec3(0.04045));
	vec3 lo = c / 12.92;
	vec3 hi = pow((c + vec3(0.055)) / 1.055, vec3(2.4));
	return mix(hi, lo, vec3(cutoff));
}

vec3 linear_to_srgb(vec3 c) {
	bvec3 cutoff = lessThanEqual(c, vec3(0.0031308));
	vec3 lo = c * 12.92;
	vec3 hi = 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055;
	return mix(hi, lo, vec3(cutoff));
}

void vertex() {
	vec4 world = MODEL_MATRIX * vec4(VERTEX, 1.0);
	world.y += ground_lift;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * world;
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	// Convert / GeneratedVisual bake I4 into alpha (RGB stays white).
	float a = clamp(albedo.a * tex.a, 0.0, 1.0);
	if (a <= 0.001) {
		discard;
	}

	vec3 back_srgb = linear_to_srgb(textureLod(screen_texture, SCREEN_UV, 0.0).rgb);
	vec3 prim_srgb = linear_to_srgb(albedo.rgb);
	ALBEDO = srgb_to_linear(mix(back_srgb, prim_srgb, a));
	// Force the transparent pass (so screen_texture is filled) while replacing the pixel.
	ALPHA = 1.0;
}
