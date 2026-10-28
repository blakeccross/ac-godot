// The sRGB curve. Palette colours and texture bytes are 8-bit gamma values, and
// Godot hands shaders linear colours, so maths that has to happen in gamma
// converts on the way in and once on the way out.
#ifndef GAMMA_GDSHADERINC
#define GAMMA_GDSHADERINC

vec3 linear_to_srgb(vec3 c) {
	bvec3 cutoff = lessThanEqual(c, vec3(0.0031308));
	vec3 lo = c * 12.92;
	vec3 hi = 1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055;
	return mix(hi, lo, vec3(cutoff));
}

vec3 srgb_to_linear(vec3 c) {
	bvec3 cutoff = lessThanEqual(c, vec3(0.04045));
	vec3 lo = c / 12.92;
	vec3 hi = pow((max(c, vec3(0.0)) + vec3(0.055)) / 1.055, vec3(2.4));
	return mix(hi, lo, vec3(cutoff));
}

// The decomp blended in 8-bit gamma; Godot blends in linear light, where the
// same alpha lifts a dark backdrop much further. For light laid over a dark
// backdrop, gamma alpha a lands where linear alpha srgb_to_linear(a) does.
float gamma_blend_alpha(float a) {
	return srgb_to_linear(vec3(clamp(a, 0.0, 1.0))).r;
}

#endif
