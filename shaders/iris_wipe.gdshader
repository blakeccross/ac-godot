shader_type canvas_item;

// Circular iris mask for SceneTransition's Style.IRIS. `progress` is the same
// 0..1 alpha channel SceneTransition already tweens for the flat fade (0 =
// fully open / game visible, 1 = fully closed / screen covered by `iris_color`),
// so it can be driven by the same tween as the plain ColorRect fill.

uniform vec4 iris_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec2 center = vec2(0.5, 0.5);
uniform vec2 rect_size = vec2(1.0, 1.0);
uniform float edge_softness : hint_range(0.0, 0.2) = 0.015;

void fragment() {
	float aspect = rect_size.x / max(rect_size.y, 1.0);
	vec2 diff = UV - center;
	diff.x *= aspect;
	float dist = length(diff);

	// Radius needed to just clear the farthest corner from `center`, so the
	// iris fully covers/uncovers the screen instead of leaving a visible ring.
	vec2 corner_dist = vec2(max(center.x, 1.0 - center.x) * aspect, max(center.y, 1.0 - center.y));
	float max_dist = length(corner_dist);

	// Give the radius `edge_softness` of overshoot past both ends of its travel: at
	// progress 1 the soft band (radius +/- edge_softness) must clear dist 0 everywhere
	// (fully closed, no residual pinhole at `center`), and at progress 0 it must clear
	// dist max_dist everywhere (fully open, no residual dot at the far corners).
	float radius = mix(max_dist + edge_softness, -edge_softness, progress);
	float alpha = smoothstep(radius - edge_softness, radius + edge_softness, dist);

	COLOR = vec4(iris_color.rgb, alpha * iris_color.a);
}
