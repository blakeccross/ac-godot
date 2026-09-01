shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_disabled, shadows_disabled, specular_disabled, ambient_light_disabled;

// obj_fallS / obj_fallSE FG waterfall — four XLU groups, one shader.
// Decomp: obj_fallS.c grpAT/BT/CT/DT + EVW_ANIME SCROLL2 (Evw_Anime_Set in ac_fallS_draw).
//
// Scroll (texels per game frame, emu64 dolphin ÷8):
//   EVW tables: AT {0,0}/{0,2}  BT {0,-3}/{0,-8}
//   DT {0,-8}/{0,0}  CT {-1,1}/{0,0}
// evw_anime.c passes (x, -y) to dolphin before UV subtract — see fragment().
//
// Linear sampling — m_rcp sets G_TF_BILERP globally; 32px maps stretched on the sheet.
uniform sampler2D tile0 : filter_linear, repeat_enable;
uniform sampler2D tile1 : filter_linear, repeat_enable;
// 0=grpAT 1=grpBT 2=grpCT 3=grpDT
uniform int waterfall_layer : hint_range(0, 3) = 1;
uniform float game_fps = 60.0;
uniform float ground_lift = 0.02;
uniform float tile0_mirror_s = 0.0;
uniform float tile0_clamp_v = 0.0;
uniform float tile1_mirror_s = 0.0;
uniform float tile1_clamp_v = 0.0;

vec3 srgb_to_linear(vec3 c) {
	bvec3 cutoff = lessThanEqual(c, vec3(0.04045));
	vec3 lo = c / 12.92;
	vec3 hi = pow((c + vec3(0.055)) / 1.055, vec3(2.4));
	return mix(hi, lo, vec3(cutoff));
}

vec3 linear_to_srgb(vec3 c) {
	bvec3 cutoff = lessThanEqual(c, vec3(0.0031308));
	vec3 lo = c * 12.92;
	vec3 hi = 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055;
	return mix(hi, lo, vec3(cutoff));
}

float mirror_fract(float u) {
	float x = fract(u * 0.5) * 2.0;
	return x > 1.0 ? 2.0 - x : x;
}

float mirror_uv(float u, float texels) {
	float half_texel = 0.5 / texels;
	return clamp(mirror_fract(u), half_texel, 1.0 - half_texel);
}

vec2 scroll_uv(vec2 uv, vec2 scroll, vec2 size, float mirror_s, float clamp_v) {
	vec2 out_uv = uv - scroll / size;
	out_uv.x = mirror_s > 0.5 ? mirror_uv(out_uv.x, size.x) : fract(out_uv.x);
	if (clamp_v > 0.5) {
		float half_texel = 0.5 / size.y;
		out_uv.y = clamp(out_uv.y, half_texel, 1.0 - half_texel);
	} else {
		out_uv.y = fract(out_uv.y);
	}
	return out_uv;
}

void vertex() {
	vec4 world = MODEL_MATRIX * vec4(VERTEX, 1.0);
	world.y += ground_lift;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * world;
}

void fragment() {
	float frame = TIME * game_fps;
	float texels = frame / 8.0;
	vec2 s0 = max(vec2(textureSize(tile0, 0)), vec2(1.0));
	vec2 s1 = max(vec2(textureSize(tile1, 0)), vec2(1.0));

// Scroll (EVW tables in obj_fallS.c). evw_anime.c negates Y before dolphin:
//   two_tex_scroll_dolphin(..., x0, -y0, ..., x1, -y1, ...).
// emu64 subtracts that offset from UV → use vec2(x, -y) * frame/8 here (same as river/splash).
	vec2 scroll0 = vec2(0.0);
	vec2 scroll1 = vec2(0.0);
	if (waterfall_layer == 0) {
		scroll1 = vec2(0.0, -2.0) * texels;
	} else if (waterfall_layer == 1) {
		scroll0 = vec2(0.0, 3.0) * texels;
		scroll1 = vec2(0.0, 8.0) * texels;
	} else if (waterfall_layer == 2) {
		scroll0 = vec2(-1.0, -1.0) * texels;
	} else {
		scroll0 = vec2(0.0, 8.0) * texels;
	}

	vec2 uv0 = scroll_uv(UV, scroll0, s0, tile0_mirror_s, tile0_clamp_v);
	vec2 uv1_base = UV;
	if (abs(s0.x - s1.x) > 0.5 || abs(s0.y - s1.y) > 0.5) {
		uv1_base = UV * (s0 / s1);
	}
	vec2 uv1 = scroll_uv(uv1_base, scroll1, s1, tile1_mirror_s, tile1_clamp_v);

	vec4 samp0 = texture(tile0, uv0);
	vec4 samp1 = texture(tile1, uv1);
	bool ia0 = waterfall_layer == 1 || waterfall_layer == 3;
	bool ia1 = waterfall_layer == 1;
	float t0 = samp0.r;
	float t1 = samp1.r;
	float t0a = ia0 ? samp0.a : t0;
	float t1a = ia1 ? samp1.a : t1;

	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float shade = mix(0.45, 1.0, clamp(dot(n, normalize(vec3(0.35, 0.9, 0.2))), 0.0, 1.0));

	vec3 out_srgb = vec3(0.0);
	float alpha = 1.0;

	if (waterfall_layer == 0) {
		// grpAT: PRIM*SHADE+ENV → t0*LOD+combined / t0*t1. Prim (200,220,255), env (20,30,40), LOD 32.
		vec3 prim = vec3(200.0, 220.0, 255.0) / 255.0;
		vec3 env = vec3(20.0, 30.0, 40.0) / 255.0;
		float lod = 32.0 / 255.0;
		vec3 combined = prim * shade + env;
		float a1 = t0 * t1;
		out_srgb = clamp(vec3(t0) * lod + combined, vec3(0.0), vec3(1.0));
		alpha = a1;
	} else if (waterfall_layer == 1) {
		// grpBT: PRIM+t0 → *SHADE+t0 / t0a*t1a*LOD. Prim (100,140,255), LOD 255.
		vec3 prim = vec3(100.0, 140.0, 255.0) / 255.0;
		vec3 combined = prim + vec3(t0);
		out_srgb = clamp(combined * shade + vec3(t0), vec3(0.0), vec3(1.0));
		alpha = t0a * t1a;
	} else if (waterfall_layer == 2) {
		// grpCT: PRIM*SHADE+ENV → t1*LOD+combined / t0*t1. Prim (200,220,255,100), env (30,40,50), LOD 47.
		vec3 prim = vec3(200.0, 220.0, 255.0) / 255.0;
		vec3 env = vec3(30.0, 40.0, 50.0) / 255.0;
		float lod = 47.0 / 255.0;
		vec3 combined = prim * shade + env;
		float a1 = t0 * t1;
		out_srgb = clamp(vec3(t1) * lod + combined, vec3(0.0), vec3(1.0));
		alpha = a1;
	} else {
		// grpDT: PRIM+t0 → *SHADE+t1 / t0a*t1. Prim (100,140,255), LOD 32 (alpha only on cycle1).
		vec3 prim = vec3(100.0, 140.0, 255.0) / 255.0;
		vec3 combined = prim + vec3(t0);
		float a1 = t0a * t1;
		out_srgb = clamp(combined * shade + vec3(t1), vec3(0.0), vec3(1.0));
		alpha = a1;
	}

	ALBEDO = srgb_to_linear(out_srgb);
	ALPHA = clamp(alpha, 0.0, 1.0);
}
