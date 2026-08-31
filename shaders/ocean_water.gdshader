shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_disabled, shadows_disabled, specular_disabled, ambient_light_disabled;

// Acre XLU ocean — decomp `grd_*_modelT` + `aFD_MakeMarinScrollInfo`.
//
// CombineLERP:
//   TEXEL1, 0, TEXEL0, TEXEL0,  TEXEL1, 0, TEXEL0, 0,
//   PRIMITIVE, 0, SHADE, COMBINED,  0, 0, 0, COMBINED
// Cycle1 RGB (TEXEL1 - 0) * TEXEL0 + TEXEL0 = TEXEL0 * (TEXEL1 + 1)
// Cycle2 RGB PRIM * SHADE + COMBINED;  A = TEXEL0.a * TEXEL1.a. Prim (60,120,255).
//
// Both tiles are IA8, so .rgb is intensity and .a is coverage. Peak alpha is only
// ~0.18, so this layer is a thin white crest wash — the blue body is the OPA
// beach2/beachB bed (prim 32,48,144) drawn underneath by beach_wet.gdshader.
//
// TEXEL0 is wave1 32x32 REPEAT/REPEAT on every band. TEXEL1 is wave2 32x64
// REPEAT/CLAMP on the shore band and wave3 32x32 REPEAT/REPEAT further out.
//
// Sampling is linear, not nearest like the rest of the project: m_rcp sets
// G_TF_BILERP globally, and these 32px cell maps are stretched over a whole acre,
// so point sampling turns the soft crests into hard single-pixel cracks.
uniform sampler2D wave1 : filter_linear, repeat_enable;
uniform sampler2D wave2 : filter_linear, repeat_enable;
uniform vec4 prim_color : source_color = vec4(0.23529412, 0.47058824, 1.0, 1.0);
uniform float game_fps = 60.0;
uniform float ground_lift = 0.02;
uniform float wave2_clamp_v = 0.0;
// G_LIGHTING is on, but acre-edge normals are faceted and turn the sheet into
// visible triangle seams, so SHADE stands in as a constant.
uniform float shade : hint_range(0.0, 1.0) = 0.85;

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

void vertex() {
	vec4 world = MODEL_MATRIX * vec4(VERTEX, 1.0);
	world.y += ground_lift;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * world;
}

void fragment() {
	float frame = TIME * game_fps;
	float wave_cos = cos(mod(frame, 300.0) / 300.0 * TAU);

	// aFD_MakeMarinScrollInfo feeds two_tex_scroll_dolphin(scroll << 1); emu64 then
	// takes sl = x << 1 over 16 subtexels, so both tiles move scroll/4 texels in T.
	float t0_texels = (frame * -0.42666667 - 7.0) / 4.0;
	float t1_texels = (32.0 * (1.0 - wave_cos)) / 4.0;

	vec2 s0 = max(vec2(textureSize(wave1, 0)), vec2(1.0));
	vec2 s1 = max(vec2(textureSize(wave2, 0)), vec2(1.0));

	// UVs are authored in tile0 texel space, so tile1 rescales by the size ratio
	// (the 32x64 shore wave2 covers V 0..0.5, not 0..1).
	vec2 uv0 = fract(UV - vec2(0.0, t0_texels / s0.y));
	vec2 uv1 = UV * (s0 / s1) - vec2(0.0, t1_texels / s1.y);
	uv1.x = fract(uv1.x);
	if (wave2_clamp_v > 0.5) {
		// GX_CLAMP T. The sampler repeats, so stop a half texel short of the edge —
		// clamping to exactly 1.0 wraps back to row 0 and streaks the shore band.
		float half_texel = 0.5 / s1.y;
		uv1.y = clamp(uv1.y, half_texel, 1.0 - half_texel);
	} else {
		uv1.y = fract(uv1.y);
	}

	vec4 t0 = texture(wave1, uv0);
	vec4 t1 = texture(wave2, uv1);

	// The combiner lerps 8-bit gamma values and Godot uploads Color uniforms already
	// linearized, so PRIM goes back to sRGB and the result converts once at the end.
	vec3 prim_srgb = linear_to_srgb(prim_color.rgb);
	vec3 rgb = clamp(prim_srgb * shade + t0.rgb * (t1.rgb + 1.0), vec3(0.0), vec3(1.0));
	ALBEDO = srgb_to_linear(rgb);
	ALPHA = clamp(t0.a * t1.a, 0.0, 1.0);
}
