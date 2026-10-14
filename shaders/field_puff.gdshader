shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert, specular_disabled;

// A dust / steam / smoke puff card (`ef_dust01`, `ef_kisha_kemuri01`), drawn billboarded
// (`auto_matrix_xlu_proc`). Its frames sit side by side in `frames`; every two ticks of its
// life (`step`) the tables pick two of them and cross-fade by `lods` (PRIM_LOD_FRAC), times
// that step's `alphas`. The frames are I4: alpha is the intensity. Colour and the eased
// opacity come in as the particle's COLOR; age is INSTANCE_CUSTOM.w.

uniform sampler2D frames : source_color, filter_linear, repeat_disable;
uniform int frame_count = 1;
uniform int steps = 1;
uniform int tile0[24];
uniform int tile1[24];
uniform float lods[24];
uniform float alphas[24];
uniform float hold = 0.0;

varying vec4 tint;
varying flat int step;

void vertex() {
	tint = COLOR;
	float age = max(INSTANCE_CUSTOM.w - hold, 0.0);
	step = clamp(int(age * 30.0), 0, steps - 1);
	vec3 s = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(INV_VIEW_MATRIX[0].xyz * s.x, 0.0),
		vec4(INV_VIEW_MATRIX[1].xyz * s.y, 0.0),
		vec4(INV_VIEW_MATRIX[2].xyz * s.z, 0.0),
		MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

float frame_alpha(int index, vec2 uv) {
	float n = float(max(frame_count, 1));
	vec2 at = vec2((clamp(uv.x, 0.0, 1.0) + float(clamp(index, 0, frame_count - 1))) / n, uv.y);
	return texture(frames, at).r;
}

void fragment() {
	float a = mix(frame_alpha(tile0[step], UV), frame_alpha(tile1[step], UV), lods[step]);
	ALBEDO = tint.rgb;
	ALPHA = a * alphas[step] * tint.a;
}
