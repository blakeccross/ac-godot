shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// The pale circle on the ground under the well spirit (`ef_circle_light_model`): PRIM
// (255, 255, 220) with the soft I4 texture as its alpha, scaled by the effect's own alpha.
uniform sampler2D tex0 : filter_linear, repeat_disable;
uniform float strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// `GX_MIRROR` on both axes: the texture is a quarter of the circle, folded out to the quad.
	vec2 uv = 1.0 - abs(mod(UV * 2.0, 2.0) - 1.0);
	float t = texture(tex0, uv).a;
	ALBEDO = vec3(1.0, 1.0, 220.0 / 255.0);
	ALPHA = clamp(t * strength, 0.0, 1.0);
}
