shader_type spatial;
// Translucent river sheet over the opaque bed: two ripple maps scroll against
// each other. Decomp reference: the `grd_*_modelT` combiner and Evw_Anime
// SCROLL2 (`aFD_texture_scroll2_data`). Colour is mix(deep, crest, a) lit by the
// field lights, plus b as a white crest. Opacity starts at base_alpha and both
// maps add to it.
// The ripple maps sample linear, not nearest like the rest of the project: they
// are 32 px cells stretched across a whole acre.
render_mode unshaded, cull_disabled, world_vertex_coords;

#include "field_shade.gdshaderinc"

uniform sampler2D ripple_texture_a : hint_default_black, filter_linear, repeat_enable;
uniform sampler2D ripple_texture_b : hint_default_black, filter_linear, repeat_enable;
uniform vec3 deep_color : source_color = vec3(0.0, 0.392, 1.0);
uniform vec3 crest_color : source_color = vec3(1.0);
uniform float base_alpha : hint_range(0.0, 1.0) = 0.14;
uniform float ripple_alpha : hint_range(0.0, 1.0) = 0.10;
// UV per second.
uniform vec2 scroll_a = vec2(-0.176, -0.176);
uniform vec2 scroll_b = vec2(0.176, -0.352);
// Metres the sheet floats above the coplanar bed.
uniform float ground_lift = 0.025;

varying vec3 vertex_shade;

void vertex() {
	VERTEX.y += ground_lift;
	vertex_shade = field_shade(normalize(NORMAL), VERTEX);
}

void fragment() {
	float a = texture(ripple_texture_a, UV + scroll_a * TIME).r;
	float b = texture(ripple_texture_b, UV + scroll_b * TIME).r;
	// Combine in the palette's gamma like every field surface, then hand linear back.
	vec3 water = mix(linear_to_srgb(deep_color), linear_to_srgb(crest_color), a) * vertex_shade;
	ALBEDO = srgb_to_linear(clamp(water + b, 0.0, 1.0));
	ALPHA = clamp(base_alpha + (a + b) * ripple_alpha, 0.0, 1.0);
}
