shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert, specular_disabled;

// A field effect card (`ef_dust01`, `ef_kisha_kemuri01`, `ef_sunahane01`, `ef_sibuki01`,
// `ef_yukihane01`, `ef_koke_suiteki01`, `ef_koke_yuki01`). Its frames sit side by side in
// `frames`; every two ticks of its life (`step`, counted from landing for drops) the tables
// pick two of them, cross-fade by `lods`, scale the card by `sizes` and its alpha by
// `alphas`. Colour (PRIM) and the eased opacity come in as the particle's COLOR; age is
// INSTANCE_CUSTOM.w. The combiners all end `COMBINED × SHADE` (lit albedo here):
//   0 PRIM                      (suiteki / sibuki)
//   1 PRIM, α = lerp(T0,T1,LOD) (dust, steam, smoke: two-tile cross-fade)
//   2 mix(PRIM, 1, T) + ENV     (koke_yuki / yukihane)
//   3 (NOISE − T)·PRIM + ENV    (sunahane)
//   4 TEXEL rgb × PRIM          (dig mud, fishing drops: textured cards)
// I4 frames carry their intensity in red; IA8 frames keep their own alpha.

uniform sampler2D frames : source_color, filter_linear, repeat_disable;
uniform int frame_count = 1;
uniform int steps = 1;
uniform int tile0[24];
uniform int tile1[24];
uniform float lods[24];
uniform float alphas[24];
uniform float sizes[24];
uniform float hold = 0.0;
// Steps count from here (drops: from hitting the ground); before it, step 0.
uniform float land_time = -1.0;
uniform int mode = 1;
uniform vec3 env : source_color = vec3(0.0);
uniform bool billboard = true;
uniform bool intensity_alpha = true;
// Table steps per second: one every two 60 Hz ticks.
const float STEP_RATE = 30.0;
// How often sunahane's noise re-rolls, per second (every 60 Hz frame).
const float NOISE_RATE = 60.0;

varying vec4 tint;
varying flat int step;

void vertex() {
	tint = COLOR;
	float age = max(INSTANCE_CUSTOM.w - hold, 0.0);
	float since = land_time >= 0.0 ? (age >= land_time ? age - land_time : -1.0) : age;
	step = since < 0.0 ? 0 : clamp(int(since * STEP_RATE), 0, steps - 1);
	VERTEX *= sizes[step];
	if (billboard) {
		vec3 s = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			vec4(INV_VIEW_MATRIX[0].xyz * s.x, 0.0),
			vec4(INV_VIEW_MATRIX[1].xyz * s.y, 0.0),
			vec4(INV_VIEW_MATRIX[2].xyz * s.z, 0.0),
			MODEL_MATRIX[3]);
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
}

vec4 frame_texel(int index, vec2 uv) {
	float n = float(max(frame_count, 1));
	vec2 at = vec2((clamp(uv.x, 0.0, 1.0) + float(clamp(index, 0, frame_count - 1))) / n, uv.y);
	vec4 t = texture(frames, at);
	if (intensity_alpha) {
		t.a = t.r;
	}
	return t;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec4 t0 = frame_texel(tile0[step], UV);
	vec3 rgb = tint.rgb;
	float a = t0.a;
	vec3 add = vec3(0.0);
	if (mode == 1) {
		a = mix(t0.a, frame_texel(tile1[step], UV).a, lods[step]);
	} else if (mode == 2) {
		rgb = mix(tint.rgb, vec3(1.0), t0.r);
		add = env;
	} else if (mode == 3) {
		float noise = hash(floor(UV * 16.0) + vec2(floor(TIME * NOISE_RATE)));
		rgb = clamp((vec3(noise) - t0.rgb) * tint.rgb + env, 0.0, 1.0);
	} else if (mode == 4) {
		rgb = t0.rgb * tint.rgb;
	}
	ALBEDO = rgb;
	EMISSION = add;
	ALPHA = a * alphas[step] * tint.a;
}
