shader_type spatial;
// Bubble card over the well. Bright pixels rise; empty ones are discarded so a
// stale framebuffer copy cannot punch a hole in the basin.
render_mode unshaded, blend_mix, depth_draw_opaque, cull_disabled, shadows_disabled,
		specular_disabled, ambient_light_disabled, fog_disabled;

#include "field_shade.gdshaderinc"

uniform sampler2D bubble_tex : source_color, filter_linear, repeat_enable;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

const vec3 LIFT = vec3(80.0 / 255.0);
const float COVERAGE = 180.0 / 255.0;
// UV per second. Up the 16×64 card.
const vec2 SCROLL = vec2(0.0, -1.40625);
const float DEPTH_BIAS = 0.03;

varying vec3 vertex_shade;

void vertex() {
	vec3 n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vertex_shade = field_shade(n, world);
	vec3 view = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	view.z += DEPTH_BIAS;
	POSITION = PROJECTION_MATRIX * vec4(view, 1.0);
}

void fragment() {
	float mask = linear_to_srgb(vec3(texture(bubble_tex, UV - SCROLL * TIME).r)).r;
	vec3 rgb = clamp(vertex_shade + LIFT, vec3(0.0), vec3(1.0));
	float a = clamp(mask * COVERAGE, 0.0, 1.0);
	if (a < 0.5 / 255.0) {
		discard;
	}
	vec3 back = linear_to_srgb(textureLod(screen_texture, SCREEN_UV, 0.0).rgb);
	ALBEDO = srgb_to_linear(mix(back, rgb, a));
	ALPHA = 1.0;
}
