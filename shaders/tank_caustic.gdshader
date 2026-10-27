shader_type spatial;
// Scrolling caustic on the tank floor. Colour is a flat tint. Alpha is the
// sum of the two masks times the vertex shade (stored in COLOR).
render_mode unshaded, cull_back, blend_mix, depth_draw_never, shadows_disabled,
		specular_disabled, ambient_light_disabled, fog_disabled;

uniform sampler2D water1 : filter_linear, repeat_enable;
uniform sampler2D water2 : filter_linear, repeat_enable;
uniform vec3 tint = vec3(0.588235, 1.0, 1.0);
// Texels per second. The two masks travel opposite ways.
uniform vec2 scroll_a = vec2(7.5, -7.5);
uniform vec2 scroll_b = vec2(-7.5, 7.5);
uniform float tile_texels = 32.0;

vec3 srgb_to_linear(vec3 c) {
	bvec3 cutoff = lessThanEqual(c, vec3(0.04045));
	vec3 lo = c / 12.92;
	vec3 hi = pow((c + vec3(0.055)) / 1.055, vec3(2.4));
	return mix(hi, lo, vec3(cutoff));
}

void fragment() {
	float scroll = TIME / tile_texels;
	// Intensity lives in alpha. RGB on these masks is white.
	float t0 = texture(water1, UV - scroll_a * scroll).a;
	float t1 = texture(water2, UV - scroll_b * scroll).a;
	ALBEDO = srgb_to_linear(tint);
	ALPHA = clamp((t0 + t1) * COLOR.r, 0.0, 1.0);
}
