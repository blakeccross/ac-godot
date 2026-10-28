shader_type spatial;
// The spotlight cone on the player-select stage: a fixed cone mask, with a
// scrolling grain that tints the beam toward grain_color and thickens it.
// Decomp reference: `grd_player_select_modelT` and its EVW SCROLL2 layer;
// colour = mix(beam, grain colour, grain), alpha = cone × (1 + grain) × opacity.
render_mode unshaded, cull_disabled, fog_disabled;

#include "gamma.gdshaderinc"

uniform sampler2D grain_texture : hint_default_black, filter_linear, repeat_enable;
uniform sampler2D cone_texture : hint_default_black, filter_linear, repeat_disable;
// The cone's wrap-baked span: mesh UVs run 0–1 across it, the cone mirrors in U.
uniform vec2 wrap_tiles = vec2(2.0, 1.0);
uniform vec3 beam_color : source_color = vec3(1.0, 1.0, 0.51);
uniform vec3 grain_color : source_color = vec3(1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.588;
// Grain UV per cone UV, and its drift in UV per second.
uniform vec2 grain_scale = vec2(2.0, 4.0);
uniform vec2 grain_scroll = vec2(-0.234375, 0.234375);

void fragment() {
	vec2 cone_uv = UV * wrap_tiles;
	float grain = texture(grain_texture, cone_uv * grain_scale + grain_scroll * TIME).r;
	// Mirrored U, stopping half a texel short of the fold so the linear tap
	// doesn't blend in the far edge.
	float half_texel = 0.5 / float(textureSize(cone_texture, 0).x);
	float u = clamp(1.0 - abs(mod(cone_uv.x, 2.0) - 1.0), half_texel, 1.0 - half_texel);
	float cone = texture(cone_texture, vec2(u, clamp(cone_uv.y, 0.0, 1.0))).r;
	// The decomp mixes 8-bit gamma values: blue 130 must not be linearized away.
	ALBEDO = srgb_to_linear(mix(linear_to_srgb(beam_color), linear_to_srgb(grain_color), grain));
	// Light on a dark stage: match the 8-bit framebuffer's gamma blend.
	ALPHA = gamma_blend_alpha(cone * (1.0 + grain) * opacity);
}
