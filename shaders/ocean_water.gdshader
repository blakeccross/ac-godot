shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_disabled, shadows_disabled, specular_disabled, ambient_light_disabled;

// Acre XLU ocean — decomp/emu64 combiner, same look for shore foam and open hex.
//
// RGB: PRIM*SHADE + t0*(t1+1)  (no separate “brighter shore foam” pass)
// A hardware: t0.a*t1.a (tiny) → floor with body_alpha over sand underdraw
//
// wave1 continuous drift; wave2/3 cosine surge. Both feed the same combiner so
// light edges / foam share one opacity register (matches AC screenshots).
uniform sampler2D wave1 : filter_nearest, repeat_enable;
uniform sampler2D wave2 : filter_nearest, repeat_enable;
uniform vec4 prim_color : source_color = vec4(0.23529412, 0.47058824, 1.0, 1.0);
uniform vec2 layer1_uv_scale = vec2(1.0, 0.5);
uniform float game_fps = 60.0;
uniform float ground_lift = 0.02;
uniform float wave2_clamp_v = 0.0;
uniform float body_alpha = 0.9;

void vertex() {
	vec4 world = MODEL_MATRIX * vec4(VERTEX, 1.0);
	world.y += ground_lift;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * world;
}

void fragment() {
	float frame = TIME * game_fps;
	float wave_cos = cos(mod(frame, 300.0) / 300.0 * TAU);

	float t0_texels = (frame * -0.42666667 - 7.0) / 4.0;
	float t1_texels = (32.0 * (1.0 - wave_cos)) / 4.0;
	vec2 s0 = max(vec2(textureSize(wave1, 0)), vec2(1.0));
	vec2 s1 = max(vec2(textureSize(wave2, 0)), vec2(1.0));

	vec2 uv0 = fract(UV - vec2(0.0, t0_texels / s0.y));

	vec2 uv1 = UV * layer1_uv_scale - vec2(0.0, t1_texels / s1.y);
	uv1.x = fract(uv1.x);
	if (wave2_clamp_v > 0.5) {
		uv1.y = clamp(uv1.y, 0.0, 1.0);
	} else {
		uv1.y = fract(uv1.y);
	}

	vec4 t0 = texture(wave1, uv0);
	vec4 t1 = texture(wave2, uv1);

	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float shade = mix(0.55, 1.0, clamp(dot(n, normalize(vec3(0.35, 0.9, 0.2))), 0.0, 1.0));

	// Same combiner path for shore foam and open hex (no shore white boost).
	vec3 combined = t0.rgb * (t1.rgb + vec3(1.0));
	// Soften the add so average wave I matches AC lavender edges, not chalk.
	vec3 tone = prim_color.rgb * shade * 0.75 + combined * 0.45;
	ALBEDO = clamp(tone, vec3(0.0), vec3(0.9, 0.92, 1.0));
	ALPHA = max(t0.a * t1.a, body_alpha);
}
