shader_type spatial;
// Bubbles rising over the wishing well: a mask scrolls up the card over the lit
// colour, lifted a little toward white.
render_mode unshaded, cull_disabled, world_vertex_coords;

#include "field_shade.gdshaderinc"

uniform sampler2D bubble_texture : hint_default_black, filter_linear, repeat_enable;
uniform vec3 lift : source_color = vec3(0.314);
uniform float opacity : hint_range(0.0, 1.0) = 0.706;
// UV per second, up the 16×64 card.
uniform vec2 scroll = vec2(0.0, 1.40625);
// Metres toward the camera, so the card sits in front of the rim.
uniform float depth_bias = 0.03;

varying vec3 vertex_shade;

void vertex() {
	vertex_shade = field_shade(normalize(NORMAL), VERTEX);
	VERTEX += normalize(CAMERA_POSITION_WORLD - VERTEX) * depth_bias;
}

void fragment() {
	float mask = texture(bubble_texture, UV + scroll * TIME).r;
	ALBEDO = srgb_to_linear(clamp(vertex_shade + linear_to_srgb(lift), 0.0, 1.0));
	ALPHA = clamp(mask * opacity, 0.0, 1.0);
}
