shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

// The well spirit's light sphere (`ef_sphere_light`, `eMH_dw`). The original maps its soft
// I4 texture onto the sphere by a hilite reflection (`Setpos_HiliteReflect_xlu_init`), i.e. by
// the surface's angle to the viewer: bright where it faces you, clear at the rim. Here that is
// the facing term itself; `strength` is the effect's PRIM alpha.
uniform vec4 tint : source_color = vec4(1.0, 1.0, 0.72, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float glow = pow(facing, 4.0) * 0.45;
	ALBEDO = tint.rgb * glow * strength;
	ALPHA = 1.0;
}
