// Sun, moon, room lamp, and the two room glows. World and InteriorLighting
// publish field_* as 0–1 colours in the same gamma as the painted textures.
// A directional light contributes colour × clamp(n · L). A point light falls
// off as 1 − (distance / radius)² and ends at the radius. The sum clamps at 1.
#ifndef FIELD_SHADE_GDSHADERINC
#define FIELD_SHADE_GDSHADERINC

#include "gamma.gdshaderinc"

global uniform vec3 field_ambient;
global uniform vec3 field_sun_color;
global uniform vec3 field_sun_dir;
global uniform vec3 field_moon_color;
global uniform vec3 field_moon_dir;
global uniform vec3 field_lamp_pos;
global uniform vec3 field_lamp_color;
global uniform float field_lamp_radius;
global uniform vec3 field_glow0_pos;
global uniform float field_glow0_radius;
global uniform vec3 field_glow1_pos;
global uniform float field_glow1_radius;
global uniform vec3 field_glow_color;

float ndotl(vec3 n, vec3 dir) {
	float len2 = dot(dir, dir);
	if (len2 < 0.001) {
		return 0.0;
	}
	return max(dot(n, dir * inversesqrt(len2)), 0.0);
}

vec3 point_light(vec3 n, vec3 world, vec3 pos, vec3 color, float radius) {
	if (radius <= 0.001) {
		return vec3(0.0);
	}
	vec3 delta = pos - world;
	float dist = length(delta);
	if (dist >= radius || dist < 0.0001) {
		return vec3(0.0);
	}
	float falloff = 1.0 - pow(dist / radius, 2.0);
	return color * falloff * max(dot(n, delta / dist), 0.0);
}

vec3 field_shade(vec3 n, vec3 world) {
	vec3 shade = field_ambient;
	shade += field_sun_color * ndotl(n, field_sun_dir);
	shade += field_moon_color * ndotl(n, field_moon_dir);
	shade += point_light(n, world, field_lamp_pos, field_lamp_color, field_lamp_radius);
	shade += point_light(n, world, field_glow0_pos, field_glow_color, field_glow0_radius);
	shade += point_light(n, world, field_glow1_pos, field_glow_color, field_glow1_radius);
	return min(shade, vec3(1.0));
}

// Multiply in the texture's gamma, then hand linear back to the renderer.
vec3 shaded_albedo(vec3 texel_linear, vec3 shade) {
	return srgb_to_linear(clamp(linear_to_srgb(texel_linear) * shade, vec3(0.0), vec3(1.0)));
}

#endif
