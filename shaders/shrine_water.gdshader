shader_type spatial;
// Wishing-well water, and the splash rim under its spout. Two scrolling masks
// multiply into a ripple that brightens the lit water colour and adds to its
// opacity. The rim runs the same shader opaque and faster.
render_mode unshaded, cull_disabled, world_vertex_coords;

#include "field_shade.gdshaderinc"

uniform sampler2D ripple_texture_a : hint_default_black, filter_linear, repeat_enable;
uniform sampler2D ripple_texture_b : hint_default_black, filter_linear, repeat_enable;
uniform vec3 water_color : source_color = vec3(0.0, 0.392, 1.0);
uniform float base_alpha : hint_range(0.0, 1.0) = 0.09;
uniform float ripple_alpha : hint_range(0.0, 1.0) = 0.15;
// UV per second.
uniform vec2 scroll_a = vec2(0.0, -2.34375);
uniform vec2 scroll_b = vec2(0.0, -1.40625);
// Metres toward the camera, so the sheet sits on the stone.
uniform float depth_bias = 0.01;

varying vec3 vertex_shade;

void vertex() {
	vertex_shade = field_shade(normalize(NORMAL), VERTEX);
	VERTEX += normalize(CAMERA_POSITION_WORLD - VERTEX) * depth_bias;
}

void fragment() {
	float ripple = texture(ripple_texture_a, UV + scroll_a * TIME).r
			* texture(ripple_texture_b, UV + scroll_b * TIME).r;
	// The decomp adds 8-bit gamma values.
	vec3 rgb = linear_to_srgb(water_color) * vertex_shade + ripple;
	ALBEDO = srgb_to_linear(clamp(rgb, 0.0, 1.0));
	ALPHA = clamp(base_alpha + ripple * ripple_alpha, 0.0, 1.0);
}
