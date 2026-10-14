shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// `act_antT_model`: black (PRIM), alpha the sum of two copies of the I4 ant texture
// scrolling different ways (`act_ant_evw_anime` SCROLL2 {2,−1} / {1,2}, texels per tick
// ÷ 8, negated Y as `Evw_Anime_Set` passes it) × PRIM.a. The DL turns on
// G_TEXTURE_GEN_LINEAR, so the coordinates come from the view-space normal, not the
// vertices; `gsSPTexture(4000, 4000)` spreads that over about two repeats of the texture.

uniform sampler2D ants : filter_linear, repeat_enable;
uniform float opacity = 1.0;
uniform float ticks = 0.0;
uniform float texgen_repeat = 2.0;

varying vec2 gen_uv;

void vertex() {
	vec3 n = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	gen_uv = vec2(n.x, -n.y) * 0.5 * texgen_repeat + 0.5;
}

void fragment() {
	vec2 size = max(vec2(textureSize(ants, 0)), vec2(1.0));
	vec2 s0 = vec2(2.0, 1.0) * ticks / 8.0 / size;
	vec2 s1 = vec2(1.0, -2.0) * ticks / 8.0 / size;
	float a = texture(ants, gen_uv - s0).r + texture(ants, gen_uv - s1).r;
	ALBEDO = vec3(0.0);
	ALPHA = clamp(a, 0.0, 1.0) * opacity;
}
