shader_type spatial;
// Glass highlight. A view-aligned texture adds to a blue tint under the field
// lights. Alpha is a flat base plus a little of the highlight.
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

#include "field_shade.gdshaderinc"

uniform sampler2D albedo_tex : filter_linear, repeat_enable;
uniform vec3 tint : source_color = vec3(0.0, 0.118, 0.471);
uniform float base_alpha = 0.117647;
uniform float texture_alpha = 0.0390625;
// Baked wrap atlas. The highlight is generated in one tile, then fit into it.
uniform vec2 wrap_tiles = vec2(1.0);
// View-space stretch. Taller than it is wide, so the streak runs down the glass.
const vec2 HIGHLIGHT_SCALE = vec2(0.732421875, 2.44140625);

varying vec3 vertex_shade;

void vertex() {
	vec3 n = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vertex_shade = field_shade(n, world);
}

void fragment() {
	vec3 n = normalize(NORMAL);
	vec2 uv = fract((n.xy * 0.5 + 0.5) * HIGHLIGHT_SCALE) / max(wrap_tiles, vec2(0.001));
	// Raw sample. The bytes are already the gamma values the tint adds.
	vec4 texel = texture(albedo_tex, uv);
	vec3 color = clamp(linear_to_srgb(tint) + texel.rgb * vertex_shade, vec3(0.0), vec3(1.0));
	ALBEDO = srgb_to_linear(color);
	ALPHA = clamp(base_alpha + texel.a * texture_alpha, 0.0, 1.0);
}
