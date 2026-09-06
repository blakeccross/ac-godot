shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled;

// Rain streak / splash (`ef_ame02_setmode` + `ef_ame02_*_modelT`).
// Combiner: RGB = PRIM * SHADE + ENV; A = TEXEL0 * PRIM_A. GX_MIRROR on UVs.
// Converted XLU I4 stores intensity in alpha (RGB white).

uniform sampler2D intensity_tex : source_color, filter_nearest;
uniform vec4 prim_color : source_color = vec4(1.0, 0.196078, 0.196078, 0.313726);
uniform vec4 env_color : source_color = vec4(0.392157, 0.882353, 0.882353, 1.0);
uniform float shade_amt = 0.28;

float mirror_coord(float u) {
	float x = fract(u * 0.5) * 2.0;
	return x <= 1.0 ? x : 2.0 - x;
}

void fragment() {
	vec2 uv = vec2(mirror_coord(UV.x), mirror_coord(UV.y));
	vec4 tex = texture(intensity_tex, uv);
	float intensity = tex.a;
	vec3 rgb = prim_color.rgb * shade_amt + env_color.rgb;
	ALBEDO = min(rgb, vec3(1.0));
	ALPHA = intensity * prim_color.a;
	if (ALPHA < 0.02) {
		discard;
	}
}
