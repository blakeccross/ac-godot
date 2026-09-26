shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert, specular_disabled;

// Field step / tumble effect quads (`ef_dust`, `ef_sandsplash`, `ef_mizutama`, `ef_yukidama`,
// `ef_yukihane`, `ef_sibuki`, `ef_hanabira`, turn footprint, body print). The combiners
// all end `COMBINED × SHADE` — lit albedo here — and take alpha from the texel × PRIM.a:
//   0 PRIM                      (suiteki / sibuki / prints: `PRIM·SHADE`)
//   1 PRIM, α = lerp(T0,T1,LOD) (dust: two-tile cross-fade by PRIM_LOD_FRAC)
//   2 mix(PRIM, 1, T) + ENV     (koke_yuki / yukihane: `(1−PRIM)·T + PRIM`, then +ENV)
//   3 (NOISE − T)·PRIM + ENV    (sunahane)
//   4 TEXEL rgb                 (hanabira: palette colour)
// I4 frames decode with α = intensity; IA8 keep their own α.

uniform int mode = 0;
uniform sampler2D tex0 : source_color, filter_linear, repeat_disable;
uniform sampler2D tex1 : source_color, filter_linear, repeat_disable;
uniform vec4 prim_color : source_color = vec4(1.0);
uniform vec4 env_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float lod_frac = 0.0;
// `auto_matrix_xlu_proc` multiplies by the camera billboard matrix.
uniform bool billboard = false;
// I4 frames export opaque RGB; the GX I4 texel's alpha *is* its intensity.
uniform bool intensity_alpha = false;

void vertex() {
	if (billboard) {
		vec3 s = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			vec4(INV_VIEW_MATRIX[0].xyz * s.x, 0.0),
			vec4(INV_VIEW_MATRIX[1].xyz * s.y, 0.0),
			vec4(INV_VIEW_MATRIX[2].xyz * s.z, 0.0),
			MODEL_MATRIX[3]
		);
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec4 t0 = texture(tex0, UV);
	vec4 t1 = texture(tex1, UV);
	if (intensity_alpha) {
		t0.a = t0.r;
		t1.a = t1.r;
	}
	vec3 rgb = prim_color.rgb;
	float a = t0.a;
	vec3 add = vec3(0.0);
	if (mode == 1) {
		a = mix(t0.a, t1.a, lod_frac);
	} else if (mode == 2) {
		rgb = mix(prim_color.rgb, vec3(1.0), t0.r);
		add = env_color.rgb;
	} else if (mode == 3) {
		float noise = hash(floor(UV * 16.0) + vec2(floor(TIME * 60.0)));
		rgb = clamp((vec3(noise) - t0.rgb) * prim_color.rgb + env_color.rgb, 0.0, 1.0);
	} else if (mode == 4) {
		rgb = t0.rgb;
	}
	ALBEDO = rgb;
	EMISSION = add;
	ALPHA = a * prim_color.a;
}
