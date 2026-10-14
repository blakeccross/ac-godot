shader_type particles;
render_mode disable_velocity, disable_force;

// One field effect particle (`FieldParticle`): a puff, a splash or a drop. Its path is a
// closed-form function of its age, so it is the same at any frame rate: launch velocity, an
// acceleration that may fade, drag per axis, an optional held start (tumble dust waits
// before it moves) and an optional landing time after which it stays put (drops). Size and
// opacity ease between two values over a window of its life; cards that lie on the ground
// keep a fixed tilt.
// `FieldParticle.offset_at` is the same maths in GDScript, for tests.
//
// CUSTOM: xyz = where it started, w = age (s).

uniform vec3 launch = vec3(0.0);
uniform vec3 accel = vec3(0.0);
// Rate (1/s) each acceleration component fades at, and each velocity component's drag.
uniform vec3 accel_fade = vec3(0.0);
uniform vec3 drag = vec3(0.0);
// An extra climb that starts at `rise_boost` m/s and eases to nothing over `rise_time`.
uniform float rise_boost = 0.0;
uniform float rise_time = 0.0;
// Seconds before it starts to move (and before its size and fade windows open).
uniform float hold = 0.0;
uniform vec2 size_from_to = vec2(0.01, 0.01);
uniform vec2 size_window = vec2(0.0, 1.0);
uniform vec2 alpha_from_to = vec2(1.0, 1.0);
uniform vec2 alpha_window = vec2(0.0, 1.0);
uniform vec3 tint : source_color = vec3(1.0);
// Seconds into its motion at which it hits the ground and stops (−1: never).
uniform float land_time = -1.0;
// Fixed lean about the world X axis (radians) for cards that are not billboards.
uniform float tilt = 0.0;

float reach(float k, float t) {
	return k < 1e-5 ? t : (1.0 - exp(-k * t)) / k;
}

float axis(float v0, float a0, float k, float ka, float t) {
	if (abs(k - ka) < 1e-4) {
		if (k < 1e-5) {
			return v0 * t + 0.5 * a0 * t * t;
		}
		return v0 * reach(k, t) + a0 * (1.0 - exp(-k * t) * (1.0 + k * t)) / (k * k);
	}
	float a = a0 / (k - ka);
	return (v0 - a) * reach(k, t) + a * reach(ka, t);
}

float ease_window(vec2 from_to, vec2 window, float t) {
	float span = max(window.y - window.x, 1e-5);
	return mix(from_to.x, from_to.y, clamp((t - window.x) / span, 0.0, 1.0));
}

void start() {
	if (RESTART_POSITION) {
		CUSTOM = vec4(EMISSION_TRANSFORM[3].xyz, 0.0);
	}
}

void process() {
	CUSTOM.w += DELTA;
	float t = max(CUSTOM.w - hold, 0.0);
	float moving = land_time >= 0.0 ? min(t, land_time) : t;
	vec3 offset = vec3(
		axis(launch.x, accel.x, drag.x, accel_fade.x, moving),
		axis(launch.y, accel.y, drag.y, accel_fade.y, moving),
		axis(launch.z, accel.z, drag.z, accel_fade.z, moving));
	if (rise_time > 0.0) {
		float r = min(moving, rise_time);
		offset.y += rise_boost * (r - r * r / (2.0 * rise_time));
	}
	float s = ease_window(size_from_to, size_window, t);
	float c = cos(tilt);
	float n = sin(tilt);
	TRANSFORM = mat4(vec4(s, 0.0, 0.0, 0.0), vec4(0.0, c * s, n * s, 0.0), vec4(0.0, -n * s, c * s, 0.0),
		vec4(CUSTOM.xyz + offset, 1.0));
	COLOR = vec4(tint, ease_window(alpha_from_to, alpha_window, t));
}
