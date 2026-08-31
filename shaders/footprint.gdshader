shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_disabled, shadows_disabled;

// XLU footprint decal (`ef_footprint` / `ef_footprint01_00_modelT`).
//
// Original: `_texture_z_light_fog_prim_xlu` — z-tested, alpha blended, lit, prim color
// from `gDPSetPrimColor` and env white. So this stays lit: a print darkens with the
// kankyo lights like the sand it sits in, instead of glowing at night.
//
// The mark is an SDF rather than the original's tile: no original art gets converted.
//
// One MultiMesh, one draw call. `now` and each instance's spawn time are CPU-side values
// from the pool script — shader TIME is not readable from GDScript, so age cannot be
// derived here from TIME alone.
//
// INSTANCE_CUSTOM: x = spawn time (same clock as `now`), y = 1 for a snow print.

uniform float now = 0.0;
uniform float life_seconds = 2.6666667;
uniform float fade_start_seconds = 1.9666667;
uniform float fade_end_seconds = 2.65;
uniform float max_alpha = 0.5882353;
uniform vec4 sand_tint : source_color = vec4(0.27450982, 0.19607843, 0.19607843, 1.0);
uniform vec4 snow_tint : source_color = vec4(0.0, 0.19607843, 0.39215687, 1.0);
// Quad width / length, so the rim can keep an even width in world units.
uniform float aspect = 0.6666667;
// Rim ellipse semi-axes, in units where the quad's length is 1.
uniform vec2 rim_radii = vec2(0.15625, 0.3385417);
// How far the rim fades either side of that ellipse. Wide on purpose: see fragment().
uniform float rim_reach = 0.0833333;
// The dish inside the rim reads far fainter than the rim itself.
uniform float interior_alpha = 0.214;
// The original mask is I4 and peaks at 7/15, so it never drives prim alpha to full.
uniform float tile_peak = 0.4666667;

varying float v_age;
varying float v_snow;

void vertex() {
	v_age = now - INSTANCE_CUSTOM.x;
	v_snow = INSTANCE_CUSTOM.y;
}

void fragment() {
	if (v_age < 0.0 || v_age >= life_seconds) {
		discard;
	}
	// The original's 16x16 I4 mask is an elliptical rim around a faint dish: intensity 7
	// on the rim, 1-2 inside, 0 outside. No toes and no distinct heel — the mark reads as
	// a soft depression, not a sole.
	//
	// It is also soft, which a crisp SDF gets wrong. That tile is magnified over a
	// 0.5 x 0.75 m quad — 3-5 cm per texel — and filtered, and its own profile ramps
	// (0, 3, 7, 5, 2) rather than stepping. So the rim fades over a couple of texels
	// either side of the ellipse instead of having tidy edges. The falloff is bounded
	// rather than gaussian: magnifying a discrete profile bilinearly gives piecewise
	// linear ramps, and a gaussian's tails wash the rim out instead of leaving the
	// defined-but-soft band the game shows.
	vec2 q = (UV - vec2(0.5)) * vec2(aspect, 1.0);
	vec2 n = q / rim_radii;
	float nl = length(n);
	// Signed distance from the rim ellipse. Dividing by the gradient converts the
	// implicit value into a length, so the falloff holds an even width all the way round
	// instead of stretching at the ends of the long axis. The 1/nl term belongs there:
	// d(|n| - 1)/dq is n/(|n| * radii), and dropping |n| overstates the slope outside
	// the ellipse and understates it inside. Clamping the gradient also parks the very
	// centre far outside the rim, where it belongs, rather than dividing by zero.
	float grad = max(length(n / rim_radii) / max(nl, 0.000001), 0.000001);
	float band = (nl - 1.0) / grad;
	float rim = 1.0 - smoothstep(0.0, rim_reach, abs(band));
	// The dish fades in over the same blur width, so its edge matches the rim's.
	float dish = 1.0 - smoothstep(-rim_reach, rim_reach, band);
	float mask = max(rim, dish * interior_alpha);
	if (mask <= 0.002) {
		discard;
	}

	float fade = 1.0 - smoothstep(fade_start_seconds, fade_end_seconds, v_age);
	ALBEDO = mix(sand_tint.rgb, snow_tint.rgb, step(0.5, v_snow));
	// Combiner alpha is `TEXEL0 * PRIMITIVE`: the mask scales prim alpha, it does not
	// replace it, so the tile's own 7/15 ceiling has to stay in the product.
	ALPHA = mask * tile_peak * max_alpha * fade;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
