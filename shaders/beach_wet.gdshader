shader_type spatial;
// Opaque wet sand and the ocean bed. Lit by the scene like the dry sand beside
// it. The texture's alpha is a wetness mask: 1 shows surface_color, 0 shows
// the wet shimmer, which pulses between two colours on the ocean's swell.
// Decomp reference: the beachA/B combiner `(PRIM − ENV) × TEXEL0 + ENV`, with
// ENV from `aFD_MakeMarinScrollInfo`. beachA's surface is sand, beachB's the
// dark-blue bed.
// The RGB is a static preview for the FileSystem dock; only alpha is read.
render_mode cull_disabled, specular_disabled;

#include "gamma.gdshaderinc"

uniform sampler2D albedo_texture : filter_nearest, repeat_enable;
uniform vec3 surface_color : source_color = vec3(0.808, 0.741, 0.580);
uniform vec3 wet_color_low : source_color = vec3(0.565, 0.502, 0.376);
uniform vec3 wet_color_high : source_color = vec3(0.729, 0.643, 0.486);
// Shared with the ocean crests so the sand darkens as the swell comes in.
uniform float swell_period = 1.6666667;
uniform float swell_phase = -1.2;

void fragment() {
	float swell = 0.5 - 0.5 * cos(TIME / swell_period * TAU + swell_phase);
	// The texture clamps in V: stop half a texel short, or the repeating sampler
	// wraps the bed (V runs 0–6) back to the dry row 0 and paints it brown.
	float half_texel = 0.5 / float(textureSize(albedo_texture, 0).y);
	float wet = texture(albedo_texture, vec2(UV.x, clamp(UV.y, half_texel, 1.0 - half_texel))).a;
	// The decomp mixes 8-bit gamma values.
	vec3 shimmer = mix(linear_to_srgb(wet_color_low), linear_to_srgb(wet_color_high), swell);
	ALBEDO = srgb_to_linear(mix(shimmer, linear_to_srgb(surface_color), wet));
	ROUGHNESS = 1.0;
}
