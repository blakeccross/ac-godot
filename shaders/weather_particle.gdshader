shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled;

// Weather particle quads (`ef_ame02` / `ef_yuki01` / `ef_hanabira01` placeholders).
// INSTANCE_CUSTOM: x = kind (0 rain, 1 splash, 2 snow, 3 sakura), y = life 0..1.

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
		// Rain streak: thin vertical capsule (billboarded, world-up).
		float d = abs(uv.x) / 0.22 + abs(uv.y) / 0.98;
		alpha = 1.0 - smoothstep(0.75, 1.05, d);
		albedo = vec3(0.85, 0.92, 1.0);
		alpha *= 0.75;
	} else if (v_kind < 1.5) {
		// Splash ring on the ground.
		float r = length(uv);
		alpha = smoothstep(0.12, 0.32, r) * (1.0 - smoothstep(0.5, 0.95, r));
		albedo = vec3(0.8, 0.9, 1.0);
		alpha *= 0.65 * v_life;
	} else if (v_kind < 2.5) {
		// Soft snow flake.
		float r = length(uv);
		alpha = 1.0 - smoothstep(0.3, 0.85, r);
		albedo = vec3(0.97, 0.98, 1.0);
		alpha *= 0.9 * clamp(v_life, 0.25, 1.0);
	} else {
		// Sakura petal: soft ellipse, pink.
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
