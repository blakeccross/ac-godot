shader_type spatial;
// Wishing-well sheet. Two scrolling masks multiply, then add to a tinted shade.
// Blend in gamma against the framebuffer: a linear blend lifts the bright crests.
render_mode unshaded, blend_mix, depth_draw_opaque, cull_disabled, shadows_disabled,
		specular_disabled, ambient_light_disabled, fog_disabled;

#include "field_shade.gdshaderinc"

uniform sampler2D tile0 : source_color, filter_linear, repeat_enable;
uniform sampler2D tile1 : source_color, filter_linear, repeat_enable;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform vec3 tint = vec3(0.0, 0.39215687, 1.0);
uniform float mask_alpha = 0.19607843;
uniform float base_alpha = 0.19607843;
// UV per second. The splash rim overrides these.
uniform vec2 scroll0 = vec2(0.0, 2.34375);
uniform vec2 scroll1 = vec2(0.0, 1.40625);
// Metres toward the camera, so the sheet sits on the stone.
uniform float depth_bias = 0.01;

varying vec3 vertex_shade;

void vertex() {
	vec3 n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vertex_shade = field_shade(n, world);
	vec3 view = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	view.z += depth_bias;
	POSITION = PROJECTION_MATRIX * vec4(view, 1.0);
}

void fragment() {
	// Grey masks. source_color returns linear; the tint multiply is in gamma.
	float t0 = linear_to_srgb(vec3(texture(tile0, UV - scroll0 * TIME).r)).r;
	float t1 = linear_to_srgb(vec3(texture(tile1, UV - scroll1 * TIME).r)).r;
	float mask = t0 * t1;
	vec3 rgb = clamp(tint * vertex_shade + vec3(mask), vec3(0.0), vec3(1.0));
	float a = clamp(mask * mask_alpha + base_alpha, 0.0, 1.0);
	vec3 back = linear_to_srgb(textureLod(screen_texture, SCREEN_UV, 0.0).rgb);
	ALBEDO = srgb_to_linear(mix(back, rgb, a));
	ALPHA = 1.0;
}
