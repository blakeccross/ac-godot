shader_type spatial;
// The Harvest Moon's reflection on the pond: a soft disc, its colour running
// from the halo to the moon by the disc's intensity, with a slow ripple
// subtracted from its opacity. Decomp reference: `ef_moon01_01_modelT`,
// colour = lerp(ENV, PRIM, disc), alpha = (disc − ripple) × PRIM.a.
render_mode unshaded, cull_disabled, shadows_disabled;

uniform sampler2D disc_tex : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D ripple_tex : hint_default_black, filter_linear, repeat_enable;
// Linear colours.
uniform vec3 moon_color = vec3(1.0, 1.0, 0.392);
uniform vec3 halo_color = vec3(0.0, 1.0, 0.784);
uniform float opacity : hint_range(0.0, 1.0) = 0.667;
// The ripple is heavily magnified (tile shift s 4 / t 3 on a 32 px map against
// the 64 px disc) and mirrored. It drifts {1, -1} at 1/8 texel per 60 Hz frame,
// T flipped.
uniform vec2 ripple_scale = vec2(0.125, 0.25);
uniform vec2 ripple_scroll = vec2(-0.234375, -0.234375);

void fragment() {
	float disc = texture(disc_tex, UV).r;
	vec2 r = UV * ripple_scale + ripple_scroll * TIME;
	float ripple = texture(ripple_tex, 1.0 - abs(mod(r, 2.0) - 1.0)).r;
	ALBEDO = mix(halo_color, moon_color, disc);
	ALPHA = clamp((disc - ripple) * opacity, 0.0, 1.0);
}
