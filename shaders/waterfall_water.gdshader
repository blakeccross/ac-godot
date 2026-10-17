shader_type spatial;
// Four XLU sheets, drawn AT → DT. AT and BT sit on the opaque cliff, so they
// correct their blend against that copy. CT and DT are drawn over those sheets
// and keep their real colour.
render_mode unshaded, blend_mix, depth_draw_opaque, cull_disabled, shadows_disabled,
		specular_disabled, ambient_light_disabled;

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
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
// 0=grpAT 1=grpBT 2=grpCT 3=grpDT
uniform int waterfall_layer : hint_range(0, 3) = 1;
// `play->game_frame` (evw_anime.c) increments once per rendered frame; the
// texel-conversion chain below it (two_tex_scroll_dolphin -> emu64 SETTILESIZE,
// verified against src/static/libforest/emu64/emu64.c) is exact — tune this
// constant, not the /8 below. Scroll is in native texels (32², or 16² for the
// AT/CT mask). 45 keeps the rate previously tuned as 180 against 4× tiles.
uniform float game_fps = 45.0;
uniform float ground_lift = 0.02;
uniform float tile0_mirror_s = 0.0;
uniform float tile0_clamp_v = 0.0;
uniform float tile1_mirror_s = 0.0;
uniform float tile1_clamp_v = 0.0;

// Outdoor kankyo light (`l_mEnv_kcolor_*`), set by World. 0–1 palette values.
global uniform vec3 field_ambient;
global uniform vec3 field_sun_color;
global uniform vec3 field_sun_dir;
global uniform vec3 field_moon_color;
global uniform vec3 field_moon_dir;

// G_LIGHTING + G_SHADING_SMOOTH: lit per vertex, then interpolated.
varying vec3 vertex_shade;

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
	vec3 n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float sun = max(dot(n, normalize(field_sun_dir)), 0.0);
	float moon = max(dot(n, normalize(field_moon_dir)), 0.0);
	vertex_shade = clamp(field_ambient + field_sun_color * sun + field_moon_color * moon, 0.0, 1.0);
	vec4 world = MODEL_MATRIX * vec4(VERTEX, 1.0);
	world.y += ground_lift;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * world;
	// Reverse-Z: a larger clip z is closer. The sheets are a decal
	// (G_DECAL_LEQUAL), so the crest has to win against the coplanar river.
	POSITION.z += 0.002 * POSITION.w;
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

	// Mesh UVs are tile0 texels (32²). AT and CT bind a 16² tile1, so that tile
	// repeats twice as fast. Scroll is subtracted in those same native texels;
	// the baked PNG size is only the mirror/clamp inset.
	vec2 native0 = vec2(32.0);
	vec2 native1 = (waterfall_layer == 0 || waterfall_layer == 2) ? vec2(16.0) : vec2(32.0);
	// SetTile_Dolphin shift_s/shift_t (emu64 `texture_matrix` shift_tbl) scale
	// the mesh coordinate, not the scroll: 1 halves it, 14 is ×4, 15 is ×2.
	//   AT tile1 (0,14)  CT tile0 (15,15)  DT tile1 (0,1); the rest are (0,0).
	// DT's half-rate mask leaves the flat card on the empty row and fade-in
	// ramp, so the sawtooth lands on the hang over the brink.
	vec2 shift0 = waterfall_layer == 2 ? vec2(2.0) : vec2(1.0);
	vec2 shift1 = waterfall_layer == 0 ? vec2(1.0, 4.0) : (waterfall_layer == 3 ? vec2(1.0, 0.5) : vec2(1.0));
	vec2 uv0 = scroll_uv(UV * shift0 - scroll0 / native0, vec2(0.0), s0, tile0_mirror_s, tile0_clamp_v);
	vec2 uv1 = scroll_uv(UV * shift1 * (native0 / native1) - scroll1 / native1, vec2(0.0), s1, tile1_mirror_s, tile1_clamp_v);

	vec4 samp0 = texture(tile0, uv0);
	vec4 samp1 = texture(tile1, uv1);
	// IA8 keeps colour in R and coverage in A. I4 is the same value in both.
	bool ia0 = waterfall_layer == 1 || waterfall_layer == 3;
	bool ia1 = waterfall_layer == 1;
	float t0 = samp0.r;
	float t1 = samp1.r;
	float t0a = ia0 ? samp0.a : t0;
	float t1a = ia1 ? samp1.a : t1;

	vec3 shade = vertex_shade;

	vec3 out_srgb = vec3(0.0);
	float alpha = 1.0;

	if (waterfall_layer == 0) {
		// grpAT. emu64 TEV: env + shade*prim + tile1*LOD, alpha t0*t1.
		// Prim (200,220,255), env (20,30,40), LOD 32.
		vec3 prim = vec3(200.0, 220.0, 255.0) / 255.0;
		vec3 env = vec3(20.0, 30.0, 40.0) / 255.0;
		float lod = 32.0 / 255.0;
		out_srgb = clamp(env + prim * shade + vec3(t1) * lod, vec3(0.0), vec3(1.0));
		alpha = t0 * t1;
	} else if (waterfall_layer == 1) {
		// grpBT. emu64 TEV: (prim + tile0)*shade + tile1, alpha t0a*t1a.
		// Prim (100,140,255). The two tiles are the same IA8 on different scrolls.
		vec3 prim = vec3(100.0, 140.0, 255.0) / 255.0;
		out_srgb = clamp((prim + vec3(t0)) * shade + vec3(t1), vec3(0.0), vec3(1.0));
		alpha = t0a * t1a;
	} else if (waterfall_layer == 2) {
		// grpCT. emu64 TEV: prim*shade + env + tile0*LOD, alpha t1*(t0+1).
		// Prim (200,220,255), env (30,40,50), LOD 47. Tile1 is only the mask.
		vec3 prim = vec3(200.0, 220.0, 255.0) / 255.0;
		vec3 env = vec3(30.0, 40.0, 50.0) / 255.0;
		float lod = 47.0 / 255.0;
		out_srgb = clamp(prim * shade + env + vec3(t0) * lod, vec3(0.0), vec3(1.0));
		alpha = clamp(t1 * (t0 + 1.0), 0.0, 1.0);
	} else {
		// grpDT. emu64 TEV: shade*prim + tile0*(1+shade). Tile1 is the crest mask
		// only (alpha t0a*t1), not a colour add — adding it clamps the lip to white.
		vec3 prim = vec3(100.0, 140.0, 255.0) / 255.0;
		out_srgb = clamp(prim * shade + vec3(t0) * (1.0 + shade), vec3(0.0), vec3(1.0));
		alpha = t0a * t1;
	}

	float a = clamp(alpha, 0.0, 1.0);
	if (waterfall_layer >= 2) {
		// CT and DT composite over BT, which is already in the framebuffer.
		// Correcting them against the cliff copy punches that sheet back out.
		ALBEDO = srgb_to_linear(out_srgb);
		ALPHA = a;
	} else {
		// Correct the linear blend against the opaque view (the cliff). A later
		// sheet still can't see the sheet under it — Godot has already copied
		// the screen — but this stops the stack from lifting to white.
		vec3 back_linear = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;
		vec3 want_linear = srgb_to_linear(mix(linear_to_srgb(back_linear), out_srgb, a));
		ALBEDO = a > 0.02 ? max((want_linear - back_linear * (1.0 - a)) / a, vec3(0.0)) : srgb_to_linear(out_srgb);
		ALPHA = a;
	}
}
