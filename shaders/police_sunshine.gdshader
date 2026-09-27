shader_type spatial;
// Police box window beam (`obj_koban_shine_modelT`, `ef_room_sunshine_police`).
// Combiner: RGB = PRIMITIVE (window sun / moon colour), A = TEXEL0 × PRIM_LOD_FRAC.
// `G_RM_AA_ZB_XLU_SURF2` / `XLU_DECAL2`: blended, depth-tested, no depth write.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled,
		specular_disabled, ambient_light_disabled, fog_disabled;

uniform vec4 prim : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// I4 coverage in alpha (`VisualWindowLight.coverage_texture`).
uniform sampler2D albedo_texture : source_color, filter_linear, repeat_enable;

void fragment() {
	ALBEDO = prim.rgb;
	ALPHA = texture(albedo_texture, UV).a * prim.a;
}
