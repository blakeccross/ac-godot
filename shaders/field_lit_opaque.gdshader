shader_type spatial;
// Same lighting as field_lit, drawn in the opaque pass. Writing ALPHA would
// put a tree-sized shell in the transparent pass, in front of the player.
render_mode unshaded, cull_disabled, shadows_disabled, specular_disabled,
		ambient_light_disabled, fog_disabled;

#include "field_shade.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_disable;

varying vec3 vertex_shade;

void vertex() {
	vec3 n = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vertex_shade = field_shade(n, world);
}

void fragment() {
	ALBEDO = shaded_albedo(texture(albedo_tex, UV).rgb, vertex_shade);
}
