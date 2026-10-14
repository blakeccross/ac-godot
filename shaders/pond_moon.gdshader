shader_type spatial;
// The Harvest Moon's reflection (`ef_moon01_01_modelT`, `ef_night13_moon`).
//
// CombineLERP: PRIMITIVE, ENVIRONMENT, TEXEL0, ENVIRONMENT,  TEXEL0, TEXEL1, PRIMITIVE, 0
//   colour = lerp(ENV, PRIM, TEXEL0); alpha = (TEXEL0 - TEXEL1) * PRIM.a.
// Prim (255, 255, 100, 170) from the effect; Env (0, 255, 200) from the model.
// Tile 0: 64x64 I4 disc, clamped. Tile 1: 32x32 I4 ripple, mirrored, shift s 4 / t 3
// (emu64 divides the coords by 16 / 8, so the ripple is heavily magnified) and scrolled
// by the model's evw SCROLL2 layer {1, -1}: x/8 texels per frame after the shift, T flipped.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D disc_tex : filter_linear, repeat_disable;
uniform sampler2D ripple_tex : filter_linear, repeat_enable;
uniform vec4 prim_color = vec4(1.0, 1.0, 0.392157, 0.666667);
uniform vec3 env_color = vec3(0.0, 1.0, 0.784314);
uniform float game_fps = 60.0;

float mirrored(float x) {
	float m = mod(x, 2.0);
	return m > 1.0 ? 2.0 - m : m;
}

void fragment() {
	float t0 = texture(disc_tex, UV).r;
	vec2 texel = UV * 64.0 / vec2(16.0, 8.0) - vec2(1.0, 1.0) * (TIME * game_fps / 8.0);
	vec2 r_uv = texel / 32.0;
	float t1 = texture(ripple_tex, vec2(mirrored(r_uv.x), mirrored(r_uv.y))).r;
	ALBEDO = mix(env_color, prim_color.rgb, t0);
	ALPHA = clamp((t0 - t1) * prim_color.a, 0.0, 1.0);
}
