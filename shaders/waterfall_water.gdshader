shader_type spatial;
// One translucent sheet of the waterfall. Four of these stack (render_priority
// 2–5, back to front), each with its own two maps, scroll and colour terms set
// by `VisualWaterMaterials`. Decomp reference: `obj_fallS` grpAT/BT/CT/DT and
// their EVW SCROLL2 tables. The four combiners all fit
//   colour  = glow + shade × (water + a × a_lit) + a × a_add + b × b_add
//   opacity = (coverage_a + a_alpha_offset) × coverage_b
// where shade is the field light at the vertex. A map's coverage is its
// intensity, or its alpha for the IA maps.
// The maps sample linear: they are 16–32 px tiles stretched over the sheet.
render_mode unshaded, cull_disabled, world_vertex_coords;

#include "field_shade.gdshaderinc"

uniform sampler2D texture_a : hint_default_black, filter_linear, repeat_enable;
uniform sampler2D texture_b : hint_default_black, filter_linear, repeat_enable;
// Each map's UV per mesh UV, and its drift in UV per second.
uniform vec2 uv_scale_a = vec2(1.0);
uniform vec2 uv_scale_b = vec2(1.0);
uniform vec2 scroll_a = vec2(0.0);
uniform vec2 scroll_b = vec2(0.0);
// Wrap modes the sampler can't express: mirrored U and clamped V.
uniform bool mirror_a_u = false;
uniform bool clamp_a_v = false;
uniform bool mirror_b_u = false;
uniform bool clamp_b_v = false;
uniform bool coverage_a_in_alpha = false;
uniform bool coverage_b_in_alpha = false;
uniform vec3 water_color : source_color = vec3(0.392, 0.549, 1.0);
uniform vec3 glow_color : source_color = vec3(0.0);
uniform float a_lit = 1.0;
uniform float a_add = 0.0;
uniform float b_add = 1.0;
uniform float a_alpha_offset = 0.0;
// Metres up off the cliff, and toward the camera so the sheet wins against the
// coplanar river where they meet.
uniform float ground_lift = 0.025;
uniform float depth_bias = 0.1;

varying vec3 vertex_shade;

float wrap_mirrored(float u, float texels) {
	// Stop half a texel short of the fold, or the repeating sampler's linear tap
	// blends in the opposite edge.
	float x = 1.0 - abs(mod(u, 2.0) - 1.0);
	return clamp(x, 0.5 / texels, 1.0 - 0.5 / texels);
}

vec4 sample_map(sampler2D tex, vec2 uv, bool mirror_u, bool clamp_v) {
	vec2 size = vec2(textureSize(tex, 0));
	if (mirror_u) {
		uv.x = wrap_mirrored(uv.x, size.x);
	}
	if (clamp_v) {
		uv.y = clamp(uv.y, 0.5 / size.y, 1.0 - 0.5 / size.y);
	}
	return texture(tex, uv);
}

void vertex() {
	vertex_shade = field_shade(normalize(NORMAL), VERTEX);
	VERTEX.y += ground_lift;
	VERTEX += normalize(CAMERA_POSITION_WORLD - VERTEX) * depth_bias;
}

void fragment() {
	vec4 map_a = sample_map(texture_a, UV * uv_scale_a + scroll_a * TIME, mirror_a_u, clamp_a_v);
	vec4 map_b = sample_map(texture_b, UV * uv_scale_b + scroll_b * TIME, mirror_b_u, clamp_b_v);
	float a = map_a.r;
	float b = map_b.r;
	float coverage_a = coverage_a_in_alpha ? map_a.a : a;
	float coverage_b = coverage_b_in_alpha ? map_b.a : b;
	// The decomp adds 8-bit gamma values.
	vec3 water = linear_to_srgb(water_color);
	vec3 rgb = linear_to_srgb(glow_color) + vertex_shade * (water + a * a_lit) + a * a_add + b * b_add;
	ALBEDO = srgb_to_linear(clamp(rgb, 0.0, 1.0));
	ALPHA = clamp((coverage_a + a_alpha_offset) * coverage_b, 0.0, 1.0);
}
