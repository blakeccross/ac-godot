shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

// Soft elliptical ground blob under actors (player / NPC). Replaces DirectionalLight
// shadows outdoors — same role as the original's circular actor shadow, not fish SDF art.

uniform float alpha = 0.42;
uniform vec4 shadow_color : source_color = vec4(0.02, 0.04, 0.06, 1.0);
// Half-axes of the ellipse in UV space (0.5 = fills the quad).
uniform vec2 radii = vec2(0.42, 0.36);
uniform float edge_softness = 0.12;

void fragment() {
	vec2 q = UV - vec2(0.5);
	float d = length(q / radii) - 1.0;
	float grad = max(length(q / (radii * radii)), 0.000001);
	float band = d / grad;
	float mask = 1.0 - smoothstep(-edge_softness, edge_softness, band);
	if (mask <= 0.002) {
		discard;
	}
	ALBEDO = shadow_color.rgb;
	ALPHA = mask * alpha;
}
