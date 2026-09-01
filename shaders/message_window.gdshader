shader_type canvas_item;
render_mode blend_mix;

// `con_kaiwa2_modelT` / `con_kaiwaname_modelT` silhouettes as an SDF, so the chrome needs
// no extracted art. The cloud is a superellipse body unioned with four end lobes; the
// nameplate is the same shape with the lobes off and the body exponent at 2 (an ellipse).

uniform vec2 rect_px = vec2(245.0, 101.7);
uniform vec4 fill_color : source_color = vec4(0.690, 0.765, 0.659, 0.85);
uniform vec4 rim_color : source_color = vec4(0.804, 0.894, 0.784, 0.95);
// Width-normalised band drawn in `rim_color` just inside the silhouette.
uniform float rim_width = 0.014;
uniform float body_axis_x = 0.465;
uniform float body_exponent = 3.0;
// Width-normalised lobe radius. Zero draws the bare body.
uniform float lobe_radius = 0.0713;
uniform float lobe_row0 = 0.3333;
uniform float lobe_row1 = 0.6667;
// Notch softness where a lobe meets the body.
uniform float union_blend = 0.012;

float smooth_union(float a, float b, float k) {
	if (k <= 0.0) {
		return min(a, b);
	}
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

// Superellipse |dx/a|^n + |dy/b|^n = 1, turned into an approximate signed distance by
// scaling the metric overshoot by the centre-to-boundary length along the same ray.
float superellipse_sd(vec2 d, vec2 axes, float n) {
	vec2 q = abs(d) / max(axes, vec2(1e-5));
	float m = pow(pow(q.x, n) + pow(q.y, n), 1.0 / n);
	return (m - 1.0) * length(d) / max(m, 1e-5);
}

void fragment() {
	float aspect = rect_px.y / max(rect_px.x, 1e-5);
	vec2 p = vec2(UV.x, UV.y * aspect);
	vec2 centre = vec2(0.5, aspect * 0.5);

	float d = superellipse_sd(p - centre, vec2(body_axis_x, aspect * 0.5), body_exponent);

	if (lobe_radius > 0.0) {
		float rows[2] = {lobe_row0 * aspect, lobe_row1 * aspect};
		float cols[2] = {lobe_radius, 1.0 - lobe_radius};
		for (int cx = 0; cx < 2; cx++) {
			for (int cy = 0; cy < 2; cy++) {
				float lobe = length(p - vec2(cols[cx], rows[cy])) - lobe_radius;
				d = smooth_union(d, lobe, union_blend);
			}
		}
	}

	// One-and-a-half source pixels of coverage, in the same width-normalised units.
	float aa = 1.5 / max(rect_px.x, 1e-5);
	float coverage = 1.0 - smoothstep(-aa, aa, d);
	float rim = smoothstep(-rim_width - aa, -rim_width + aa, d);

	vec4 col = mix(fill_color, rim_color, rim);
	COLOR = vec4(col.rgb, col.a * coverage);
}
