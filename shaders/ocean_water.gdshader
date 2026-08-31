shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_disabled, shadows_disabled, specular_disabled, ambient_light_disabled;

// Acre XLU ocean — decomp grd_*_modelT + aFD_MakeMarinScrollInfo.
//
// Combiner (emu64): RGB = PRIM*SHADE + t0*(t1+1);  A = t0.a*t1.a
// PRIM (60,120,255). Shore wave2 32×64 CLAMP T; open wave3 32×32 REPEAT.
//
// Decomp shore acres (grd_s_m_*) also draw OPA beach2 first with PRIM
// (32,48,144) — that dark-blue underdraw + fog is why the water reads blue
// even though XLU alpha is tiny. Godot stands in with a river-ENV body.
//
// wave2 beach-side rows are high-A / near-zero I (solid clear band). Masking
// with A alone paints that band opaque out to the coarse mesh edge → jagged
// sand line. Gate shore ALPHA on intensity too so sand shows above the foam
// crest (curvy I edge) and the mesh silhouette never becomes the shoreline.
uniform sampler2D wave1 : filter_nearest, repeat_enable;
uniform sampler2D wave2 : filter_nearest, repeat_enable;
uniform vec4 prim_color : source_color = vec4(0.23529412, 0.47058824, 1.0, 1.0);
uniform vec4 body_color : source_color = vec4(0.0, 0.39215687, 1.0, 1.0);
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

	// aFD_MakeMarinScrollInfo + two_tex_scroll_dolphin: (scroll<<1)<<1 → ΔT = scroll/4.
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

	// Flat shade — acre-edge normals otherwise facet the sheet into visible seams.
	float shade = 0.85;
	bool shore = wave2_clamp_v > 0.5;

	// River-ENV blue body (stand-in for OPA beach2 + fog). wave1 hex only.
	vec3 body = body_color.rgb * shade;
	float scales = smoothstep(0.45, 0.9, t0.r);
	body = mix(body * 0.88, mix(body, prim_color.rgb * shade, 0.35), scales * 0.55);

	// wave2/3 foam crest — light top layer, does not replace the blue body.
	float foam;
	if (shore) {
		foam = smoothstep(0.35, 0.85, t1.r) * mix(0.25, 0.85, t1.a) * 0.65;
	} else {
		foam = smoothstep(0.5, 0.9, t1.r) * t1.a * 0.14;
	}
	vec3 foam_col = mix(body, vec3(0.82, 0.9, 1.0), shore ? 0.75 : 0.4);
	ALBEDO = mix(body, foam_col, clamp(foam, 0.0, 1.0));

	if (shore) {
		// Hardware A is t0.a×t1.a. wave2's beach-side band is high A but I≈0;
		// the curvy crash is the foam crest (rising I). Require both so the
		// clear band stays see-through and the mesh edge cannot silhouette.
		float crest = smoothstep(0.12, 0.48, t1.r);
		float mask = clamp(t1.a * mix(0.55, 1.0, t0.a) * crest, 0.0, 1.0);
		ALPHA = mask;
	} else {
		ALPHA = body_alpha;
	}
}
