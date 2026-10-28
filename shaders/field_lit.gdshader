shader_type spatial;
// Textured surfaces lit by the field lights. Cutouts stay on this shader.
// A solid shell uses field_lit_opaque: writing ALPHA draws in the transparent
// pass, and a large mesh then sorts in front of the player.
render_mode unshaded, cull_disabled, shadows_disabled, specular_disabled,
		ambient_light_disabled;

#include "field_shade.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_disable;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.0;

varying vec3 vertex_shade;

void vertex() {
	vec3 n = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vertex_shade = field_shade(n, world);
}

void fragment() {
	vec4 texel = texture(albedo_tex, UV);
	ALBEDO = shaded_albedo(texel.rgb, vertex_shade);
	ALPHA = texel.a;
	if (alpha_scissor_threshold > 0.0) {
		ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;
	}
}
