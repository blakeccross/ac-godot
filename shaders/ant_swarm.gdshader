shader_type spatial;
// An ant swarm on dropped food: black, with opacity from two copies of the ant
// map crawling different ways. The coordinates come from the view-space normal
// (G_TEXTURE_GEN_LINEAR), not the mesh UVs. Decomp reference: `act_antT_model`
// and `act_ant_evw_anime` SCROLL2 {2,−1} / {1,2}.
render_mode unshaded, cull_disabled, shadows_disabled;

uniform sampler2D ants : hint_default_black, filter_linear, repeat_enable;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
// `gsSPTexture(4000, 4000)` spreads the normal over about two repeats.
uniform float texgen_repeat = 2.0;
// UV per second: 1/8 texel per 60 Hz frame on the 32 px map, Y flipped.
uniform vec2 scroll_a = vec2(-0.46875, -0.234375);
uniform vec2 scroll_b = vec2(-0.234375, 0.46875);

varying vec2 gen_uv;

void vertex() {
	vec3 n = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
	gen_uv = vec2(n.x, -n.y) * 0.5 * texgen_repeat + 0.5;
}

void fragment() {
	float a = texture(ants, gen_uv + scroll_a * TIME).r + texture(ants, gen_uv + scroll_b * TIME).r;
	ALBEDO = vec3(0.0);
	ALPHA = clamp(a, 0.0, 1.0) * opacity;
}
