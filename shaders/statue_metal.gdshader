shader_type spatial;
// The station statue (`obj_{s,w}_douzou`, `ac_douzou`), coloured per rank by
// `aDOU_actor_draw_before` (PRIM / ENV by `statue_rank`).
//
// Body and name plate: CombineLERP(TEXEL0, 0, PRIMITIVE, ENVIRONMENT, ...) × SHADE
//   → colour = TEXEL0 · PRIM + ENV, lit.
// Face and mouth: CombineLERP(0, 0, 0, ENVIRONMENT,  TEXEL0, 0, ENVIRONMENT, 0) × SHADE
//   → colour = ENV, alpha = TEXEL0 (the player's eye / mouth I4 on segments 8 / 9).

uniform sampler2D tex : filter_linear, repeat_enable;
uniform vec3 prim_color : source_color = vec3(1.0, 1.0, 0.0);
uniform vec3 env_color : source_color = vec3(0.392, 0.118, 0.0);
uniform bool decal = false;

void fragment() {
	float t = texture(tex, UV).r;
	if (decal) {
		ALBEDO = env_color;
		if (t < 0.5) {
			discard;
		}
	} else {
		ALBEDO = clamp(t * prim_color + env_color, 0.0, 1.0);
	}
	ROUGHNESS = 0.6;
	METALLIC = 0.0;
}
