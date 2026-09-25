shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

// `rom_train_out_shineglass_modelT`: RGB = PRIM; A = TEXEL0 × TEXEL1 × PRIM_LOD_FRAC.
// Tile 0 = shine I4 (64×8, CLAMP/CLAMP), scrolled by `Two_Scrollx1` (the exit scroll).
// Tile 1 = glass I4 (16×16, CLAMP/CLAMP, shift_t 15 = ×2) at a fixed origin, so in tile-0
// normalised UV it samples (4u, v).
uniform sampler2D shine_tex : filter_nearest, repeat_disable;
uniform sampler2D glass_tex : filter_nearest, repeat_disable;
uniform vec4 prim_color : source_color = vec4(1.0);
uniform float lod_frac = 0.0;
// Tile-0 origin in normalised S (negative as the tile origin grows).
uniform float shine_offset = 0.0;

void fragment() {
	float shine = texture(shine_tex, vec2(UV.x + shine_offset, UV.y)).a;
	float glass = texture(glass_tex, vec2(UV.x * 4.0, UV.y)).r;
	ALBEDO = prim_color.rgb;
	ALPHA = shine * glass * lod_frac;
}
