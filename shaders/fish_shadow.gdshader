shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

// Fish shadow on the water (`act_gyoei02` / `act_gyoei02_00_modelT`).
//
// Original: `_texture_z_light_fog_prim_xlu` over a flat quad, scaled by
// `aGYO_shadow_scale[size] * 0.02` with X multiplied by a further 0.4, so the shadow is
// always 2.5x longer than it is wide. `gDPSetPrimColor(..., aGYO_prim_f[t], 0, 0, 0, alpha)`
// sets prim RGB to black and uses the ramp as the *LOD fraction*, which cross-fades two of
// the four `act_gyoei02_*_int_i4` tiles. That cross-fade is the tail sway.
//
// This is unshaded, unlike the footprint decal: the original's shadow reads as a hole in
// the water rather than a lit surface, and a lit black quad goes muddy at dusk.
//
// The four tiles are not converted — no original art is imported. Instead the body is an
// SDF: a tapered capsule bent by `body_flex`, which is driven from `aGYO_prim_f` on the CPU
// so the 20-frame, 2-frames-per-entry cadence is exactly the original's.

// -1..1 through the sway, from `FishSize.body_blend` remapped off `aGYO_prim_f`.
uniform float body_flex = 0.0;
uniform float alpha = 1.0;
// Quad length over width, so the SDF can work in square space and stay round-ended.
uniform float aspect = 0.4;
uniform vec4 shadow_color : source_color = vec4(0.02, 0.05, 0.07, 1.0);
// Half-length and half-width of the body inside the quad, in UV units.
uniform vec2 body_radii = vec2(0.17, 0.4);
// How far the silhouette fades at its edge. The original is a magnified I4 tile, so the
// rim is soft rather than crisp.
uniform float edge_softness = 0.075;
// How far the tail end swings, in UV units, at full flex.
uniform float sway = 0.075;
// The nose end barely moves; the tail does the work.
uniform float sway_bias = 1.6;
// I4 art peaks at 7/15, and combiner alpha is TEXEL0 * PRIMITIVE, so the tile never drives
// prim alpha to full.
uniform float tile_peak = 0.4666667;

void fragment() {
	// Work in a space where the body's long axis is Y and one unit is one quad length.
	vec2 q = (UV - vec2(0.5)) * vec2(aspect, 1.0);

	// Along the body, 0 at the nose and 1 at the tail. UV.y grows towards the tail because
	// the quad is drawn with the facing along +Z and the mesh is rotated to match.
	float along = clamp(UV.y, 0.0, 1.0);
	// Bend the spine instead of shearing the whole quad: a fish shadow pivots about its
	// head, so lateral offset has to grow towards the tail. Raising `along` to a power
	// keeps the nose almost still while the tail sweeps.
	float spine = sway * body_flex * pow(along, sway_bias);
	q.x -= spine;

	// Tapered capsule: the half-width shrinks towards the tail so the silhouette has a
	// head and a point, not a lozenge. 1.0 at the nose down to 0.35 at the tail.
	float taper = mix(1.0, 0.35, along);
	vec2 radii = vec2(body_radii.x * taper, body_radii.y);
	float d = length(q / radii) - 1.0;
	// Convert the implicit ellipse value into a length so the edge fade keeps an even width
	// all the way round instead of stretching at the ends of the long axis.
	float grad = max(length(q / (radii * radii)), 0.000001);
	float band = d / grad;

	float mask = 1.0 - smoothstep(-edge_softness, edge_softness, band);
	if (mask <= 0.002) {
		discard;
	}

	ALBEDO = shadow_color.rgb;
	ALPHA = mask * tile_peak * alpha;
}
