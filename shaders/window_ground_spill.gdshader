shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled, ambient_light_disabled;

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 0.588, 0.47);
uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_disable;
// 1 GX above the acre so the fan is not coplanar with grass (`G_RM_AA_ZB_XLU_DECAL2`).
uniform float ground_lift = 0.05;

void vertex() {
	vec4 world = MODEL_MATRIX * vec4(VERTEX, 1.0);
	world.y += ground_lift;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * world;
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	ALBEDO = albedo.rgb;
	ALPHA = albedo.a * tex.a;
}
