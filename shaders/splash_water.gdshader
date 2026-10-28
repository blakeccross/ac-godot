shader_type spatial;
// Foam where the river drops into the sea. Streaks scroll down through a fixed
// foam mask. The mask sets the opacity and adds a pale foam colour on top.
// Decomp reference: the mouth `sprash` combiner `(PRIM + T0) × SHADE + T1`,
// alpha `T1 × PRIM.a`. foam_color tones the T1 add down from white so the
// mouth reads as blue foam rather than a white slab.
// Both maps mirror in U (the mouth is one half, folded) and sample linear.
render_mode unshaded, cull_disabled, world_vertex_coords;

#include "field_shade.gdshaderinc"

uniform sampler2D streak_texture : hint_default_black, filter_linear, repeat_enable;
uniform sampler2D foam_texture : hint_default_black, filter_linear, repeat_enable;
uniform vec3 water_color : source_color = vec3(0.392, 0.549, 1.0);
uniform vec3 foam_color : source_color = vec3(0.667, 0.753, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.784;
// UV per second.
uniform vec2 streak_scroll = vec2(0.0, -1.0546875);
// The foam map's UV per mesh UV.
uniform vec2 foam_scale = vec2(1.0, 0.5);
// Metres the sheet floats above the river and ocean.
uniform float ground_lift = 0.0375;

varying vec3 vertex_shade;

// Mirrored repeat that stops half a texel short of each fold: the sampler
// repeats, so a linear tap on the fold would blend in the opposite edge and
// leave a dark seam down the middle of the mouth.
float mirror_u(float u, sampler2D tex) {
	float x = 1.0 - abs(mod(u, 2.0) - 1.0);
	float half_texel = 0.5 / float(textureSize(tex, 0).x);
	return clamp(x, half_texel, 1.0 - half_texel);
}

void vertex() {
	VERTEX.y += ground_lift;
	vertex_shade = field_shade(normalize(NORMAL), VERTEX);
}

void fragment() {
	vec2 uv_streak = UV + streak_scroll * TIME;
	vec2 uv_foam = UV * foam_scale;
	float streak = texture(streak_texture, vec2(mirror_u(uv_streak.x, streak_texture), uv_streak.y)).r;
	float foam = texture(foam_texture, vec2(mirror_u(uv_foam.x, foam_texture), uv_foam.y)).r;
	vec3 rgb = (linear_to_srgb(water_color) + streak) * vertex_shade + linear_to_srgb(foam_color) * foam;
	ALBEDO = srgb_to_linear(clamp(rgb, 0.0, 1.0));
	ALPHA = clamp(foam * opacity, 0.0, 1.0);
}
