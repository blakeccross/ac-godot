shader_type spatial;
// Lamplight thrown on the ground in front of a lit window: a flat colour whose
// opacity is the texture's coverage × albedo.a. Decomp reference:
// `*_window_model`, RGB = PRIM, A = TEXEL0 × PRIM_LOD_FRAC.
// Coverage is linear filtered: nearest makes a hard slab from the 16 px tile.
render_mode unshaded, cull_disabled, world_vertex_coords;

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 0.588, 0.25);
uniform sampler2D albedo_texture : hint_default_white, filter_linear, repeat_disable;
// Metres above the ground, so the fan is not coplanar with the grass.
uniform float ground_lift = 0.05;

void vertex() {
	VERTEX.y += ground_lift;
}

void fragment() {
	ALBEDO = albedo.rgb;
	ALPHA = clamp(albedo.a * texture(albedo_texture, UV).a, 0.0, 1.0);
}
