shader_type spatial;
// Scrolling caustic on the tank floor. Colour is a flat tint. Opacity is the
// sum of the two masks times the vertex shade (stored in COLOR).
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D ripple_texture_a : hint_default_black, filter_linear, repeat_enable;
uniform sampler2D ripple_texture_b : hint_default_black, filter_linear, repeat_enable;
uniform vec3 tint : source_color = vec3(0.588, 1.0, 1.0);
// UV per second. The two masks travel opposite ways.
uniform vec2 scroll_a = vec2(-0.234375, 0.234375);
uniform vec2 scroll_b = vec2(0.234375, -0.234375);

void fragment() {
	// Intensity lives in alpha. RGB on these masks is white.
	float a = texture(ripple_texture_a, UV + scroll_a * TIME).a;
	float b = texture(ripple_texture_b, UV + scroll_b * TIME).a;
	ALBEDO = tint;
	ALPHA = clamp((a + b) * COLOR.r, 0.0, 1.0);
}
