shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_disabled, shadows_disabled, specular_disabled, ambient_light_disabled;

// River-mouth sprash — decomp combiner with softer add so Godot does not chalk.
// RGB: (PRIM+t0)*SHADE + t1; A: t1*PRIM.a. Prim (100,140,255,200).
// Seg 0x09 Evw {0,-6}/{0,0} → ΔT = 6*frame/8. Tile1 shift_t=1.
uniform sampler2D sprash_c : filter_nearest, repeat_enable;
uniform sampler2D sprash_a : filter_nearest, repeat_enable;
uniform vec4 prim_color : source_color = vec4(0.39215687, 0.54901963, 1.0, 0.78431374);
uniform float game_fps = 60.0;
uniform float ground_lift = 0.03;

// Godot uploads Color uniforms already linearized. The combiner works on 8-bit
// gamma values and TEXEL0/1 arrive raw, so PRIM goes back to sRGB for the cycles
// and the result converts once.
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

void vertex() {
	vec4 world = MODEL_MATRIX * vec4(VERTEX, 1.0);
	world.y += ground_lift;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * world;
}

void fragment() {
	float frame = TIME * game_fps;
	float texels = 6.0 * frame / 8.0;
	vec2 s0 = max(vec2(textureSize(sprash_c, 0)), vec2(1.0));
	vec2 uv0 = vec2(mirror_fract(UV.x), fract(UV.y - texels / s0.y));
	vec2 uv1 = vec2(mirror_fract(UV.x), fract(UV.y * 0.5));
	float t0 = texture(sprash_c, uv0).r;
	float t1 = texture(sprash_a, uv1).r;

	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float shade = mix(0.5, 1.0, clamp(dot(n, normalize(vec3(0.35, 0.9, 0.2))), 0.0, 1.0));
	vec3 prim_srgb = linear_to_srgb(prim_color.rgb);
	vec3 combined = prim_srgb + vec3(t0);
	// Tint the TEXEL1 add with prim so the mouth stays blue-foam, not a white slab.
	vec3 out_srgb = clamp(
		combined * shade + mix(prim_srgb, vec3(1.0), 0.45) * t1, vec3(0.0), vec3(1.0)
	);
	ALBEDO = srgb_to_linear(out_srgb);
	ALPHA = clamp(t1 * prim_color.a, 0.0, 1.0);
}
