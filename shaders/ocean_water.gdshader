shader_type spatial;
// Translucent wave crests over the opaque ocean bed (`beach_wet.gdshader` draws
// the blue body underneath). Decomp reference: the `grd_*_modelT` XLU combiner
// and `aFD_MakeMarinScrollInfo`. Colour is water_color × brightness + a × (b + 1),
// and opacity is a × b, so this layer is only a thin white crest wash (peak
// alpha ≈ 0.18).
// Map a slides steadily up the shore. Map b swells back and forth on a cosine.
// The shore band's map b clamps in V (its crest line must not repeat), and the
// open-water bands repeat.
// The maps sample linear: they are 32 px cells stretched across a whole acre.
render_mode unshaded, cull_disabled, world_vertex_coords;

#include "gamma.gdshaderinc"

uniform sampler2D wave_texture_a : hint_default_black, filter_linear, repeat_enable;
uniform sampler2D wave_texture_b : hint_default_black, filter_linear, repeat_enable;
uniform vec3 water_color : source_color = vec3(0.235, 0.471, 1.0);
// Stands in for the vertex light. Acre-edge normals are faceted and would show
// the triangles.
uniform float brightness : hint_range(0.0, 1.0) = 0.85;
// UV per second.
uniform vec2 scroll_a = vec2(0.0, 0.15);
// Map b's swell: the seconds per cycle, and the map-a UV it travels at the peak.
uniform float swell_period = 1.6666667;
uniform float swell_reach = 0.5;
// Map b's UV per map-a UV (the shore map is twice as tall as map a).
uniform vec2 wave_b_scale = vec2(1.0);
uniform bool wave_b_clamp_v = false;
// Metres the sheet floats above the coplanar bed.
uniform float ground_lift = 0.025;

void vertex() {
	VERTEX.y += ground_lift;
}

void fragment() {
	float swell = 0.5 - 0.5 * cos(TIME / swell_period * TAU);
	vec2 uv_a = UV + scroll_a * TIME;
	vec2 uv_b = (UV - vec2(0.0, swell * swell_reach)) * wave_b_scale;
	if (wave_b_clamp_v) {
		// The sampler repeats, so stop half a texel short of the edge or the
		// linear tap wraps back to row 0 and streaks the shore band.
		float half_texel = 0.5 / float(textureSize(wave_texture_b, 0).y);
		uv_b.y = clamp(uv_b.y, half_texel, 1.0 - half_texel);
	}
	// Both maps are IA: rgb is intensity, a is coverage.
	vec4 a = texture(wave_texture_a, uv_a);
	vec4 b = texture(wave_texture_b, uv_b);
	vec3 rgb = linear_to_srgb(water_color) * brightness + a.rgb * (b.rgb + 1.0);
	ALBEDO = srgb_to_linear(clamp(rgb, 0.0, 1.0));
	ALPHA = clamp(a.a * b.a, 0.0, 1.0);
}
