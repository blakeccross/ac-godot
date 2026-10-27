shader_type spatial;
// Aquarium bubble (`ef_museum5_awa1`). Faces the camera like `eEL_AutoMatrixXlu`.
// Draw size is `card_scale` on the pipeline quad. The texture already has the
// combiner baked in: white over cyan, alpha = mask × 150.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled,
		specular_disabled, ambient_light_disabled, fog_disabled;

uniform sampler2D bubble_tex : filter_nearest, repeat_disable;
// Multiplier on the pipeline quad (±0.4). x is the width, y the height.
uniform vec2 card_scale = vec2(1.0);

void vertex() {
	VERTEX.x *= card_scale.x;
	VERTEX.y *= card_scale.y;
	// Face the camera. Same construction as the field-particle cards. Node scale
	// stays 1; `card_scale` is the draw size.
	vec3 s = vec3(
			length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			vec4(INV_VIEW_MATRIX[0].xyz * s.x, 0.0),
			vec4(INV_VIEW_MATRIX[1].xyz * s.y, 0.0),
			vec4(INV_VIEW_MATRIX[2].xyz * s.z, 0.0),
			MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec4 texel = texture(bubble_tex, UV);
	if (texel.a < 0.04) {
		discard;
	}
	ALBEDO = texel.rgb;
	ALPHA = texel.a;
}
