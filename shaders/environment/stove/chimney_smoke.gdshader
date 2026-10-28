shader_type particles;
// Chimney smoke: every puff relaxes toward the air's velocity (wind with its gust, plus the
// warm plume's rise), so a gust bends the whole plume at once, not only new puffs.

uniform vec3 wind = vec3(0.0); // world m/s, gust included
uniform float rise_mps = 0.7;
uniform float drag = 1.1; // 1/s: how fast a puff takes up the air's speed
uniform float exit_speed = 1.3;
uniform float spread_m = 0.06;
uniform float size_start = 0.4;
uniform float size_end = 3.2;
uniform float spin = 0.5;
uniform float opacity = 0.6;
uniform vec3 tint = vec3(0.62, 0.62, 0.64);

uint hash(uint x) {
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = (x >> uint(16)) ^ x;
	return x;
}

float rand(inout uint seed) {
	seed = hash(seed);
	return float(seed % uint(65536)) / 65535.0;
}

void start() {
	uint seed = hash(NUMBER + uint(1) + RANDOM_SEED);
	vec2 jitter = vec2(rand(seed) - 0.5, rand(seed) - 0.5) * spread_m;
	if (RESTART_POSITION) {
		TRANSFORM = mat4(1.0);
		TRANSFORM[3].xyz = EMISSION_TRANSFORM[3].xyz + vec3(jitter.x, 0.0, jitter.y);
	}
	if (RESTART_VELOCITY) {
		VELOCITY = vec3(jitter.x * 6.0, exit_speed * (0.8 + 0.4 * rand(seed)), jitter.y * 6.0);
	}
	// x: angle, y: age 0..1, w: per-puff random.
	CUSTOM = vec4(rand(seed) * 6.2832, 0.0, 0.0, rand(seed));
}

void process() {
	CUSTOM.y = min(CUSTOM.y + DELTA / LIFETIME, 1.0);
	float age = CUSTOM.y;
	vec3 air = wind + vec3(0.0, rise_mps * (1.0 - 0.6 * age), 0.0);
	VELOCITY = mix(air, VELOCITY, exp(-drag * DELTA));
	CUSTOM.x += spin * (CUSTOM.w - 0.5) * DELTA;
	float size = mix(size_start, size_end, sqrt(age)) * (0.8 + 0.4 * CUSTOM.w);
	TRANSFORM[0].xyz = vec3(size, 0.0, 0.0);
	TRANSFORM[1].xyz = vec3(0.0, size, 0.0);
	TRANSFORM[2].xyz = vec3(0.0, 0.0, size);
	float alpha = smoothstep(0.0, 0.06, age) * (1.0 - smoothstep(0.35, 1.0, age));
	COLOR = vec4(tint, alpha * opacity);
}
