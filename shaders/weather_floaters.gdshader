shader_type particles;
render_mode disable_velocity, disable_force;

// Snow flakes and cherry petals (`aWeatherSnow_*` / `aWeatherSakura_*`). Each starts at the top
// of a box on the camera look-at (the emitter's origin = `Camera2_getCenterPos_p`), falls at
// its own speed, wobbles round a small circle, rides the wind (snow) or drifts east (petals),
// and wraps round the box: off a side back in at the other, below the floor back to the top.
// Snow shrinks away over the last stretch above the floor; petals tumble. Metres / seconds.

uniform float box_x = 5.0;
uniform float box_z_back = 10.0;
uniform float box_z_front = 9.0;
uniform float top_height = 11.5;
uniform float floor_height = 2.0;
// Fall speed range (m/s, negative is down).
uniform vec2 fall_speed = vec2(-7.5, -1.5);
// Wind (snow) or the petals' eastward drift, m/s.
uniform vec3 drift = vec3(0.0);
uniform float wobble_radius = 0.3;
// Wobble turn rate range (rad/s): base and random extra.
uniform vec2 wobble_rate = vec2(0.9, 1.5);
uniform float size = 0.2;
// Shrink to nothing over this height above the floor (0 = never).
uniform float shrink_band = 0.0;
// Petals tumble at these rates (rad/s); zero leaves the card upright for a billboard.
uniform vec3 tumble_rate = vec3(0.0);

float rand(inout uint seed) {
	seed = seed * 747796405u + 2891336453u;
	uint word = ((seed >> ((seed >> 28u) + 4u)) ^ seed) * 277803737u;
	return float((word >> 22u) ^ word) / 4294967295.0;
}

vec3 wobble(float phase) {
	return vec3(sin(phase), 0.0, cos(phase)) * wobble_radius;
}

mat3 euler_yxz(vec3 r) {
	float cx = cos(r.x), sx = sin(r.x);
	float cy = cos(r.y), sy = sin(r.y);
	float cz = cos(r.z), sz = sin(r.z);
	mat3 rx = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, cx, sx), vec3(0.0, -sx, cx));
	mat3 ry = mat3(vec3(cy, 0.0, -sy), vec3(0.0, 1.0, 0.0), vec3(sy, 0.0, cy));
	mat3 rz = mat3(vec3(cz, sz, 0.0), vec3(-sz, cz, 0.0), vec3(0.0, 0.0, 1.0));
	return ry * rx * rz;
}

void place(inout mat4 xf, vec3 base, float phase, float age, float spin_seed, float floor_y) {
	vec3 pos = base + wobble(phase);
	float s = size;
	if (shrink_band > 0.0) {
		s *= clamp((pos.y - floor_y) / shrink_band, 0.0, 1.0);
	}
	mat3 basis = mat3(1.0);
	if (tumble_rate != vec3(0.0)) {
		// `suMtxMakeSRT(0.05, rot2, rot1, rot2)`.
		vec3 r = vec3(spin_seed * 6.2831853) + tumble_rate * age;
		basis = euler_yxz(vec3(r.z, r.y, r.z));
	}
	xf = mat4(vec4(basis[0] * s, 0.0), vec4(basis[1] * s, 0.0), vec4(basis[2] * s, 0.0), vec4(pos, 1.0));
}

void start() {
	if (RESTART_POSITION) {
		uint seed = NUMBER * 1973u + RANDOM_SEED * 9277u + 26699u;
		vec3 c = EMISSION_TRANSFORM[3].xyz;
		vec3 base = c + vec3(
			mix(-box_x, box_x, rand(seed)), top_height, mix(-box_z_back, box_z_front, rand(seed)));
		VELOCITY = vec3(0.0, mix(fall_speed.x, fall_speed.y, rand(seed)), 0.0);
		// x: wobble phase, y: age, z: wobble rate, w: tumble seed.
		CUSTOM = vec4(0.0, 0.0, wobble_rate.x + rand(seed) * wobble_rate.y, rand(seed));
		place(TRANSFORM, base, 0.0, 0.0, CUSTOM.w, c.y + floor_height);
	}
}

void process() {
	vec3 c = EMISSION_TRANSFORM[3].xyz;
	vec3 base = TRANSFORM[3].xyz - wobble(CUSTOM.x);
	base += (VELOCITY + drift) * DELTA;
	CUSTOM.x = mod(CUSTOM.x + CUSTOM.z * DELTA, 6.2831853);
	CUSTOM.y += DELTA;
	if (base.x < c.x - box_x) {
		base.x += 2.0 * box_x;
	} else if (base.x > c.x + box_x) {
		base.x -= 2.0 * box_x;
	}
	if (base.z < c.z - box_z_back) {
		base.z += box_z_back + box_z_front;
	} else if (base.z > c.z + box_z_front) {
		base.z -= box_z_back + box_z_front;
	}
	float floor_y = c.y + floor_height;
	if (base.y < floor_y) {
		// Back to the top, keeping its place in the fall.
		base.y += top_height - floor_height;
	}
	place(TRANSFORM, base, CUSTOM.x, CUSTOM.y, CUSTOM.w, floor_y);
}
