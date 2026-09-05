shader_type spatial;
// 1:1 acre XLU river (`grd_*_modelT` + Evw_Anime SCROLL2).
// Decomp: ac_field_draw aFD_texture_scroll2_data, grd_*_modelT combiner.
//
// CombineLERP:
//   PRIMITIVE, ENVIRONMENT, TEXEL0, ENVIRONMENT,  1, 0, TEXEL0, TEXEL1,
//   COMBINED, 0, SHADE, TEXEL0,  COMBINED, 0, PRIM_LOD_FRAC, PRIMITIVE
// Prim (0, 50, 255,255,255, 50); Env (0, 100, 255, 255).
//
// Scroll: {+1,-1}/{−1,-2} → evw flips T → dolphin (x,y)=(frame,frame)/(-frame,2frame).
// emu64 UV: (s - sl/16)/w with sl = x<<1 → texel scroll = x/8 per game_frame @ 60 Hz.
// Subtracting that offset matches SetTileSize (PC port uses the same emu64 path).
// Sampling is linear, not nearest like the rest of the project: m_rcp sets
// G_TF_BILERP globally, and these 32px cell maps are stretched down a whole acre,
// so point sampling turns the soft cells into a hard pixel grid.
//
// RDP blends XLU in 8-bit gamma; Godot blend_mix is linear HDR. At this layer's
// 0.20–0.38 alpha that over-lifts water1 foam (measured crest ~135 vs hardware ~90).
// Composite in sRGB against the screen, then emit opaque ALBEDO.
render_mode unshaded, blend_mix, depth_draw_opaque, cull_disabled, shadows_disabled,
		specular_disabled, ambient_light_disabled, fog_disabled;

uniform sampler2D water1 : filter_linear, repeat_enable;
uniform sampler2D water2 : filter_linear, repeat_enable;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform vec4 prim_color : source_color = vec4(1.0, 1.0, 1.0, 0.19607843);
uniform vec4 env_color : source_color = vec4(0.0, 0.39215687, 1.0, 1.0);
uniform float game_fps = 60.0;
uniform float ground_lift = 0.02;

// Godot uploads Color uniforms already linearized. The combiner works on 8-bit
// gamma values and TEXEL0/1 arrive raw, so PRIM/ENV go back to sRGB for the
// cycles and the result converts once. Mixing the two spaces blew the ripples
// out to white early (red was +72 at TEXEL0 = 0.15).
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
	float texels = frame / 8.0;
	vec2 s0 = max(vec2(textureSize(water1, 0)), vec2(1.0));
	vec2 s1 = max(vec2(textureSize(water2, 0)), vec2(1.0));
	vec2 uv0 = UV - vec2(1.0, 1.0) * texels / s0;
	vec2 uv1 = UV - vec2(-1.0, 2.0) * texels / s1;
	float t0 = texture(water1, uv0).r;
	float t1 = texture(water2, uv1).r;

	// Cycle1 RGB: (PRIM - ENV) * TEXEL0 + ENV
	vec3 combined = mix(linear_to_srgb(env_color.rgb), linear_to_srgb(prim_color.rgb), t0);
	// G_LIGHTING shade from world-space normal (outdoor key ≈ AC sun).
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float shade = mix(0.45, 1.0, clamp(dot(n, normalize(vec3(0.35, 0.9, 0.2))), 0.0, 1.0));
	// Cycle2 RGB: COMBINED * SHADE + TEXEL0
	vec3 rgb_srgb = clamp(combined * shade + vec3(t0), vec3(0.0), vec3(1.0));
	// Cycle2 A: COMBINED * PRIM_LOD_FRAC + PRIM  (LOD=50, A=50)
	float a = clamp(clamp(t0 + t1, 0.0, 1.0) * 0.19607843 + 0.19607843, 0.0, 1.0);

	vec3 back_srgb = linear_to_srgb(textureLod(screen_texture, SCREEN_UV, 0.0).rgb);
	ALBEDO = srgb_to_linear(mix(back_srgb, rgb_srgb, a));
	// Keep the transparent pass (screen_texture filled) while replacing the pixel.
	ALPHA = 1.0;
}
