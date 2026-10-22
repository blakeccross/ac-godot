shader_type spatial;
// Player-select spotlight (`grd_player_select_modelT` + `EVW_ANIME_TYPE_SCROLL2`).
// Tile 0 is the I4 grain (`rom_open_spot2`, shift 15, REPEAT). Tile 1 is the I8 cone
// (`rom_open_spot`, MIRROR S / CLAMP T). emu64 TEV for this combiner:
//   rgb  = env * (1 - grain) + prim * grain
//   alpha = cone * lod * (1 + grain)
// with lod in TEVREG0.a (`SetPrimColor` level 150). Grain scrolls; the cone does not.
//
// Scroll chain (same as the waterfall): `game_frame` × (1, 1), evw negates Y, dolphin
// `<< 1`, emu64 subtracts `sl/16` → `frame/8` texels. Shift 15 scales the mesh UV ×2,
// not the scroll. `game_fps` is the play-move rate; do not retune the /8.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled,
		specular_disabled, ambient_light_disabled, fog_disabled;

uniform sampler2D grain_tex : filter_linear, repeat_enable;
uniform sampler2D cone_tex : filter_linear, repeat_disable;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
// Wrap-bake span of the cone (`wrap_tiles` on the baked material). UVs are 0–1 across it.
uniform vec2 wrap_tiles = vec2(2.0, 1.0);
uniform float game_fps = 60.0;
uniform vec3 env_color : source_color = vec3(1.0, 1.0, 0.5098);
uniform vec3 prim_color : source_color = vec3(1.0);
uniform float lod_frac = 0.588235;
uniform float beam_opacity = 0.6;

vec3 srgb_to_linear(vec3 c) {
	bvec3 cutoff = lessThanEqual(c, vec3(0.04045));
	vec3 lo = c / 12.92;
	vec3 hi = pow((c + vec3(0.055)) / 1.055, vec3(2.4));
	return mix(hi, lo, vec3(cutoff));
}

vec3 linear_to_srgb(vec3 c) {
	bvec3 cutoff = lessThanEqual(c, vec3(0.0031308));
	vec3 lo = c * 12.92;
	vec3 hi = 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055;
	return mix(hi, lo, vec3(cutoff));
}

float mirror_fract(float u) {
	float x = fract(u * 0.5) * 2.0;
	return x > 1.0 ? 2.0 - x : x;
}

float mirror_uv(float u, float texels) {
	float half_texel = 0.5 / texels;
	return clamp(mirror_fract(u), half_texel, 1.0 - half_texel);
}

void fragment() {
	float texels = TIME * game_fps / 8.0;
	// Pipeline stored UVs in cone space (V × 32/64) then divided U by the mirror span.
	vec2 cone_uv = vec2(UV.x * wrap_tiles.x, UV.y * wrap_tiles.y);
	// Grain tile is 32². Undo the V rescale, then shift 15 (×2). Scroll is tile 0 only.
	vec2 grain_uv = vec2(cone_uv.x, cone_uv.y * 2.0) * 2.0 - vec2(texels, -texels) / 32.0;
	float grain = texture(grain_tex, grain_uv).r;
	float cone = texture(cone_tex, vec2(mirror_uv(cone_uv.x, 32.0), clamp(cone_uv.y, 0.0, 1.0))).r;
	// Godot uploads a Color already linearized. The combiner mixes 8-bit framebuffer
	// bytes, so ENV/PRIM go back to sRGB first. Red and green are 1 and survive
	// either way; blue (130) does not, and the beam reads as a harsh yellow.
	vec3 out_srgb = mix(linear_to_srgb(env_color), linear_to_srgb(prim_color), grain);
	float alpha = clamp(cone * lod_frac * (1.0 + grain) * beam_opacity, 0.0, 1.0);
	// GC blends in the 8-bit framebuffer. Match that over the opaque pass (floor, K.K.).
	// One path for every alpha: a cutoff here draws a bright ring where the two blends meet.
	vec3 back_linear = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;
	vec3 want_linear = srgb_to_linear(mix(linear_to_srgb(back_linear), out_srgb, alpha));
	ALBEDO = alpha > 0.0
			? max((want_linear - back_linear * (1.0 - alpha)) / max(alpha, 0.0001), vec3(0.0))
			: vec3(0.0);
	ALPHA = alpha;
}
