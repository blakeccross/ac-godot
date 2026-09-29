shader_type spatial;
// Able Sisters window beam (`ef_room_sunshine`, `room_lightL` / `room_lightR`).
// Both combiners take RGB = PRIMITIVE (window sun / moon colour). The floor patch
// (`light_floor01_mode`) takes A = TEXEL0 × PRIM; the shaft (`light_shine01_mode`,
// texture off) takes A = SHADE × PRIM, so it fades out towards the floor.
// `G_RM_ZB_CLD_SURF`: blended, depth-tested, no depth write.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled,
		specular_disabled, ambient_light_disabled, fog_disabled;

uniform vec4 prim : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// I4 coverage in alpha (`VisualWindowLight.coverage_texture`). Unused by the shaft.
uniform sampler2D albedo_texture : source_color, filter_linear, repeat_enable;
uniform bool shade_alpha = false;

void fragment() {
	ALBEDO = prim.rgb;
	float coverage = shade_alpha ? COLOR.a : texture(albedo_texture, UV).a;
	ALPHA = coverage * prim.a;
}
