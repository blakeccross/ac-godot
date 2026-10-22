shader_type spatial;
// Player-select actor shade (`end_1` / guitar, `G_LIGHTING` + `G_SHADING_SMOOTH`).
// RSP: clamp(ambient + max(N·L, 0) * sun) × texel, per vertex, then Gouraud.
// Godot's Lambert divides that dot by PI, so the multiply stays in this shader.
render_mode unshaded, cull_disabled, shadows_disabled, specular_disabled,
		ambient_light_disabled, fog_disabled;

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_disable;
uniform vec3 ambient_color : source_color = vec3(0.1176, 0.1176, 0.3137);
uniform vec3 sun_color : source_color = vec3(1.0, 1.0, 0.7843);
// Toward the sun, world space. Steeper than the table `(0, 89, 79)` — see
// `IntroKkStage.CHARACTER_SUN_DIR`.
uniform vec3 sun_direction = vec3(0.0, 115.0, 55.0);
// 0 keeps an opaque surface. Face quads use the imported scissor threshold.
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.0;

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

void vertex() {
	vec3 n = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	float ndotl = max(dot(n, normalize(sun_direction)), 0.0);
	// Godot uploads the palette already linearized. The RSP adds ambient and sun
	// in 8-bit, so a lit vert clamps to white — including blue. Doing that add in
	// linear leaves the forehead cream and the muzzle almost as bright.
	vec3 shade = linear_to_srgb(ambient_color) + linear_to_srgb(sun_color) * ndotl;
	vertex_shade = min(shade, vec3(1.0));
}

void fragment() {
	vec4 texel = texture(albedo_tex, UV);
	ALBEDO = srgb_to_linear(linear_to_srgb(texel.rgb) * vertex_shade);
	ALPHA = texel.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;
}
