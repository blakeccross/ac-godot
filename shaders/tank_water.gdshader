shader_type spatial;
// Water surface on the small tanks. Colour is the texture times the vertex
// colour. Alpha is a flat base plus a little of the texture.
render_mode unshaded, cull_back, blend_mix, depth_draw_never, shadows_disabled,
		specular_disabled, ambient_light_disabled, fog_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear, repeat_disable;
uniform float base_alpha = 0.352941;
uniform float texture_alpha = 0.1953125;

void fragment() {
	vec4 texel = texture(albedo_tex, UV);
	ALBEDO = texel.rgb * COLOR.rgb;
	ALPHA = clamp(base_alpha + texel.a * texture_alpha, 0.0, 1.0);
}
