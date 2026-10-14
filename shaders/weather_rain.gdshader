shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled;

// Rain streak / splash particle (`ef_ame02_setmode` + `ef_ame02_*_modelT`), drawn on the
// `GPUParticles3D` rain and splash emitters.
// Combiner: RGB = PRIM * SHADE + ENV; A = TEXEL0 * PRIM_A. GX_MIRROR on UVs.
// Converted XLU I4 stores intensity in alpha (RGB white).

uniform sampler2D intensity_tex : source_color, filter_nearest;
uniform vec4 prim_color : source_color = vec4(1.0, 0.196078, 0.196078, 0.313726);
uniform vec4 env_color : source_color = vec4(0.392157, 0.882353, 0.882353, 1.0);
uniform float shade_amt = 0.28;
// Size of the card on its authored ±1 verts (the rain streak is thin and tall).
uniform vec3 card_scale = vec3(1.0);
// Rain turns round the vertical to face the camera (`suMtxMakeSRT` with the eye's yaw);
// splashes face it fully (`play->billboard_matrix`).
uniform bool full_billboard = false;
// Flipbook pass: draw only during frame `frame_index` of `frame_count` across the particle's
// life (`(8 - timer) >> 1` for the four splash cards). −1 draws throughout.
uniform int frame_index = -1;
uniform int frame_count = 1;

float mirror_coord(float u) {
	float x = fract(u * 0.5) * 2.0;
	return x <= 1.0 ? x : 2.0 - x;
}

void vertex() {
	VERTEX *= card_scale;
	if (frame_index >= 0) {
		int frame = int(clamp(INSTANCE_CUSTOM.y, 0.0, 0.999) * float(frame_count));
		if (frame != frame_index) {
			VERTEX = vec3(0.0);
		}
	}
	if (full_billboard) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	} else {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
			vec4(0.0, 1.0, 0.0, 0.0),
			vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
			MODEL_MATRIX[3]);
	}
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 uv = vec2(mirror_coord(UV.x), mirror_coord(UV.y));
	vec4 tex = texture(intensity_tex, uv);
	float intensity = tex.a;
	vec3 rgb = prim_color.rgb * shade_amt + env_color.rgb;
	ALBEDO = min(rgb, vec3(1.0));
	ALPHA = intensity * prim_color.a;
	if (ALPHA < 0.02) {
		discard;
	}
}
