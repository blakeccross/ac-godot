shader_type spatial;
render_mode unshaded, depth_draw_opaque, cull_disabled, shadows_disabled, specular_disabled, ambient_light_disabled;

// 1:1 OPA wet-sand (beachA/B). Combine: (PRIM-ENV)*TEXEL0+ENV.
// ENV from aFD_MakeMarinScrollInfo: same 300-frame cosine as ocean, phase -1.2.
// beachA prim (206,189,148); beachB prim (32,48,144). GX_REPEAT S / GX_CLAMP T.
uniform sampler2D albedo_texture : filter_nearest, repeat_enable;
uniform vec4 prim_color : source_color = vec4(0.80784315, 0.74117649, 0.58039218, 1.0);
uniform float game_fps = 60.0;

void fragment() {
	float frame = TIME * game_fps;
	float beach_cos = cos(mod(frame, 300.0) / 300.0 * TAU - 1.2);
	vec3 env_color = vec3(
		(144.0 + (beach_cos * -21.0 + 21.0)) / 255.0,
		(128.0 + (beach_cos * -18.0 + 18.0)) / 255.0,
		(96.0 + (beach_cos * -14.0 + 14.0)) / 255.0
	);
	vec2 uv = vec2(fract(UV.x), clamp(UV.y, 0.0, 1.0));
	float t0 = texture(albedo_texture, uv).r;
	ALBEDO = mix(env_color, prim_color.rgb, t0);
	ALPHA = 1.0;
}
