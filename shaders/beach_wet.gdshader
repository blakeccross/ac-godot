shader_type spatial;
render_mode depth_draw_opaque, cull_disabled, specular_disabled;

// OPA wet-sand / ocean bed (beachA/B). Same BG path as dry sand:
// `_texture_z_light_fog_prim_bg` + G_LIGHTING + G_FOG + G_RM_FOG_SHADE_A.
//
// Cycle1: (PRIM - ENV) * TEXEL0 + ENV. Cycle2: COMBINED * SHADE.
// ENV from aFD_MakeMarinScrollInfo: same 300-frame cosine as ocean, phase -1.2.
// beachA prim (206,189,148); beachB prim (32,48,144). GX_REPEAT S / GX_CLAMP T.
//
// Convert bakes a static mid-dark ENV into RGB for FileSystem preview; I lives in
// alpha. Runtime mixes ENV/PRIM from that I and leaves SHADE/fog to the scene —
// dry sand / FG props use lit StandardMaterial3D with the same kankyo lights.
// Do not add an env delta onto baked RGB; do not fake an unshaded N·L.
uniform sampler2D albedo_texture : filter_nearest, repeat_enable;
uniform vec4 prim_color : source_color = vec4(0.80784315, 0.74117649, 0.58039218, 1.0);
uniform float game_fps = 60.0;

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

void fragment() {
	float frame = TIME * game_fps;
	float beach_cos = cos(mod(frame, 300.0) / 300.0 * TAU - 1.2);
	vec3 env_srgb = vec3(
		(144.0 + (beach_cos * -21.0 + 21.0)) / 255.0,
		(128.0 + (beach_cos * -18.0 + 18.0)) / 255.0,
		(96.0 + (beach_cos * -14.0 + 14.0)) / 255.0
	);
	// The sampler repeats both axes, so the CLAMP T edge has to stop a half texel
	// short of 1.0. beachB V runs 0..6, so most of the bed clamps to exactly 1.0,
	// and a repeat wrap there reads row 0 (I=0) — the floor goes ENV-brown instead
	// of PRIM-blue, and the shore reads as a hard golden band against dry sand.
	float half_texel = 0.5 / float(textureSize(albedo_texture, 0).y);
	vec2 uv = vec2(fract(UV.x), clamp(UV.y, half_texel, 1.0 - half_texel));
	vec4 samp = texture(albedo_texture, uv);
	float t0 = samp.a;
	if (samp.a > 0.99 && abs(samp.r - samp.g) < 0.02 && abs(samp.g - samp.b) < 0.02) {
		t0 = samp.r;
	}
	// Godot uploads a Color uniform already linearized, but the combiner lerps 8-bit
	// gamma values, so PRIM has to go back to sRGB for the mix. Linearizing it twice
	// darkens the I=1 end and it stops matching the dry-sand texture it sits against.
	vec3 prim_srgb = linear_to_srgb(prim_color.rgb);
	ALBEDO = srgb_to_linear(mix(env_srgb, prim_srgb, t0));
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	ALPHA = 1.0;
}
