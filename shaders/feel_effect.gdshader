shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// Villager feel effects (`ef_pun`, `ef_siawase`, `ef_think`, `ef_namida`, `ef_kaze`, …).
// Almost every one draws `PRIMITIVE, ENVIRONMENT, TEXEL, ENVIRONMENT`: the texel's intensity
// blends ENV → PRIM, alpha is the texel's alpha × PRIM.a. The two-tile ones first mix the
// tiles by PRIM_LOD_FRAC, and some scroll a tile (`Evw_Anime` SCROLL2 /
// `two_tex_scroll_dolphin`, texels per tick ÷ 8 as on the waterfall).
//   alpha_mode 0  T0.a
//              1  mix(T0.a, T1.a, lod)
//              2  T0.a · T1.a
//              3  mix(T0.a, T1.a, ENV.a)
// I4 tiles export opaque grey; their alpha is the intensity.

// Raw intensities: the combiner reads texels as numbers, not colours.
uniform sampler2D tex0 : filter_linear, repeat_enable;
uniform sampler2D tex1 : filter_linear, repeat_enable;
uniform bool two_tiles = false;
// `ef_pun01_00`: colour from T0 alone, only the alpha cross-fades the frames.
uniform bool color_t0 = false;
uniform vec4 prim_color : source_color = vec4(1.0);
uniform vec4 env_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float lod_frac = 0.0;
uniform int alpha_mode = 0;
// `ef_neboke_awa01`: alpha takes ENV.a rather than PRIM.a.
uniform bool alpha_from_env = false;
uniform bool i4_0 = false;
uniform bool i4_1 = false;
uniform bool mirror0 = false;
uniform bool mirror1 = false;
// Texels the tile has moved, already scaled to the tick.
uniform vec2 scroll0 = vec2(0.0);
uniform vec2 scroll1 = vec2(0.0);
// UV scale of each tile: the tile's shift, and tile 1's size against tile 0's (the mesh
// UVs count tile-0 repeats).
uniform vec2 uv0_scale = vec2(1.0);
uniform vec2 uv1_scale = vec2(1.0);

float mirror_fract(float u) {
	float x = fract(u * 0.5) * 2.0;
	return x > 1.0 ? 2.0 - x : x;
}

vec2 wrap_uv(vec2 uv, bool mirror) {
	return mirror ? vec2(mirror_fract(uv.x), mirror_fract(uv.y)) : fract(uv);
}

void fragment() {
	vec2 s0 = max(vec2(textureSize(tex0, 0)), vec2(1.0));
	vec4 t0 = texture(tex0, wrap_uv(UV * uv0_scale - scroll0 / s0, mirror0));
	if (i4_0) {
		t0.a = t0.r;
	}
	float c = t0.r;
	float a = t0.a;
	if (two_tiles) {
		vec2 s1 = max(vec2(textureSize(tex1, 0)), vec2(1.0));
		vec4 t1 = texture(tex1, wrap_uv(UV * uv1_scale - scroll1 / s1, mirror1));
		if (i4_1) {
			t1.a = t1.r;
		}
		c = color_t0 ? t0.r : mix(t0.r, t1.r, lod_frac);
		if (alpha_mode == 1) {
			a = mix(t0.a, t1.a, lod_frac);
		} else if (alpha_mode == 2) {
			a = t0.a * t1.a;
		} else if (alpha_mode == 3) {
			a = mix(t0.a, t1.a, env_color.a);
		}
	}
	ALBEDO = mix(env_color.rgb, prim_color.rgb, c);
	ALPHA = clamp(a * (alpha_from_env ? env_color.a : prim_color.a), 0.0, 1.0);
}
