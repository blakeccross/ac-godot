shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled;

// Snow / sakura placeholders, plus procedural rain if `ef_ame02_*` is missing.
// INSTANCE_CUSTOM: x = kind (0 rain, 2 snow, 3 sakura), y = life 0..1.

varying float v_kind;
varying float v_life;

void vertex() {
	v_kind = INSTANCE_CUSTOM.x;
	v_life = INSTANCE_CUSTOM.y;
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float alpha = 0.0;
	vec3 albedo = vec3(1.0);

	if (v_kind < 0.5) {
		// Fallback rain streak (real path uses `weather_rain.gdshader` + ef_ame02).
		float d = abs(uv.x) / 0.15 + abs(uv.y) / 0.98;
		alpha = 1.0 - smoothstep(0.7, 1.05, d);
		albedo = vec3(0.55, 0.92, 0.95);
		alpha *= 0.31;
	} else if (v_kind < 2.5) {
		float r = length(uv);
		alpha = 1.0 - smoothstep(0.3, 0.85, r);
		albedo = vec3(0.97, 0.98, 1.0);
		alpha *= 0.9 * clamp(v_life, 0.25, 1.0);
	} else {
		vec2 p = vec2(uv.x * 1.15, uv.y * 1.6);
		float r = length(p);
		alpha = 1.0 - smoothstep(0.35, 0.9, r);
		albedo = vec3(1.0, 0.72, 0.82);
		alpha *= 0.85 * clamp(v_life, 0.3, 1.0);
	}

	if (alpha < 0.02) {
		discard;
	}
	ALBEDO = albedo;
	ALPHA = alpha;
}
