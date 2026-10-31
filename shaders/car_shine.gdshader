shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

// The gleam that sweeps a freshly washed car (`ef_car01_modelT` in `eCar_Blight_dw`): the
// original scrolls two hilite-reflected textures over the body at (3, 7) texels a tick. Here two
// diagonal bands cross it in opposite directions, strongest where the surface faces the viewer.
uniform float phase = 0.0;
uniform float strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float a = sin((UV.x * 5.0 + UV.y * 11.0) - phase * 9.0) * 0.5 + 0.5;
	float b = sin((UV.x * 7.0 - UV.y * 9.0) + phase * 13.0) * 0.5 + 0.5;
	float bands = smoothstep(0.6, 1.0, a * b + 0.15);
	ALBEDO = vec3(1.0, 1.0, 0.85) * bands * facing * strength;
	ALPHA = 1.0;
}
