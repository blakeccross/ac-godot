shader_type spatial;
// Museum entrance window beam (`obj_museum1_shine`, `ef_room_sunshine_museum`), the
// stained glass the light passes through.
// Shaft (`obj_museum1_shine_model`, two cycles):
//   RGB = TEXEL0 × ENV_ALPHA (180) + PRIMITIVE × PRIM_ALPHA (75)
//   A   = TEXEL0 × TEXEL1 × PRIM_LOD_FRAC; TEXEL1 is the I4 fade on its own tile (UV2).
// Floor patch (`obj_museum1_shine_modelT`): RGB = TEXEL0 × PRIMITIVE, A = TEXEL0 × PRIM_LOD_FRAC.
// `G_RM_ZB_XLU_SURF2` / `XLU_DECAL2`: blended, depth-tested, no depth write.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled,
		specular_disabled, ambient_light_disabled, fog_disabled;

// RGB = window sun / moon colour, A = beam alpha (PRIM_LOD_FRAC).
uniform vec4 prim : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D albedo_texture : source_color, filter_linear, repeat_disable;
uniform sampler2D fade_texture : filter_linear, repeat_disable;
uniform bool shaft = false;

const float ENV_ALPHA = 180.0 / 255.0;
const float PRIM_ALPHA = 75.0 / 255.0;

void fragment() {
	vec4 texel0 = texture(albedo_texture, UV);
	if (shaft) {
		ALBEDO = texel0.rgb * ENV_ALPHA + prim.rgb * PRIM_ALPHA;
		ALPHA = texel0.a * texture(fade_texture, UV2).r * prim.a;
	} else {
		ALBEDO = texel0.rgb * prim.rgb;
		ALPHA = texel0.a * prim.a;
	}
}
