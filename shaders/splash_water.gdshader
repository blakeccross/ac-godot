shader_type spatial;
// Foam where the river drops into the sea. Streaks scroll down through a fixed
// foam mask, which only sets the opacity.
// Decomp reference: the mouth `sprash` combiner reads `(PRIM + T0) × SHADE + T1`,
// but emu64 swaps in a hand-written TEV for it (`emu64.c`, combine cases):
// stage 0 `T0 + SHADE × T0`, stage 1 `PREV + SHADE × PRIM`, alpha `PRIM.a × T1.a`.
// T1 never reaches the colour, so the mouth is shaded blue with faint streaks.
// Both maps mirror in U (the mouth is one half, folded) and sample linear.
render_mode unshaded, cull_disabled, world_vertex_coords;

#include "field_shade.gdshaderinc"

uniform sampler2D streak_texture : hint_default_black, filter_linear, repeat_enable;
uniform sampler2D foam_texture : hint_default_black, filter_linear, repeat_enable;
uniform vec3 water_color : source_color = vec3(0.392, 0.549, 1.0);
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
	vec3 rgb = linear_to_srgb(water_color) * vertex_shade + streak * (1.0 + vertex_shade);
	ALBEDO = srgb_to_linear(clamp(rgb, 0.0, 1.0));
	ALPHA = clamp(foam * opacity, 0.0, 1.0);
}
