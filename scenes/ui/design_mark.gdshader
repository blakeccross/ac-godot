shader_type canvas_item;

// `LERP(PRIMITIVE, ENVIRONMENT, TEXEL0, ENVIRONMENT)` with alpha = TEXEL0 alpha, for the
// design editor marks whose PRIM/ENV change with the mode (`des_win_marking2T_model`).
// The IA texture carries intensity in R.
uniform vec4 prim : source_color = vec4(1.0);
uniform vec4 env : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	COLOR = vec4(mix(env.rgb, prim.rgb, t.r), t.a);
}
