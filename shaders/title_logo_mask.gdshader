shader_type spatial;
// Title logo backdrop (`aAL_back_draw`, `G_CC_BACK`) and TM mark (`aAL_tm_draw`, `G_CC_TM`).
//
// Both draw an I4 texture whose combiner is
//   RGB   = PRIMITIVE
//   alpha = TEXEL0 (* PRIM.a for the backdrop)
// and on GX an I4 texel's alpha *is* its intensity. The converted GLB keeps the intensity in
// RGB and only a 0/255 cutout in alpha, so the soft falloff has to come from `.r` here.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled,
		specular_disabled, ambient_light_disabled, fog_disabled;

// Raw sampler: intensity is used as alpha directly, not as an sRGB colour.
uniform sampler2D mask : filter_linear, repeat_disable;
uniform vec4 prim_color : source_color = vec4(0.3137, 0.2353, 0.0, 1.0);
// PRIM alpha (`actor->back_opacity` / 255). 1.0 for the TM mark.
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	float intensity = texture(mask, UV).r;
	ALBEDO = prim_color.rgb;
	ALPHA = intensity * opacity;
}
