// HFN production snow adaptation of ProfesorShader's
// "Wind Driven Falling Particles" (CC0).
// Source: https://godotshaders.com/shader/wind-driven-falling-particles-leaves-petals-feathers/
//
// WeatherController is the only wind authority. Existing particles continuously
// steer toward the live wind vector, so gusts and direction wander affect flakes
// already in flight instead of only newly spawned flakes.

shader_type particles;
render_mode keep_data, collision_use_scale;

#include "res://shaders/environment/weather/snow_door_barrier.gdshaderinc"

uniform vec4 color : source_color = vec4(0.94, 0.97, 1.0, 0.96);
uniform vec3 box_emit_size = vec3(24.0, 1.8, 18.0);
uniform vec3 wind_velocity = vec3(0.0);
uniform float fall_speed_min : hint_range(0.1, 5.0, 0.05) = 1.35;
uniform float fall_speed_max : hint_range(0.1, 5.0, 0.05) = 2.15;
uniform float turbulence_strength : hint_range(0.0, 4.0, 0.05) = 0.25;
uniform float drag : hint_range(0.1, 12.0, 0.1) = 5.4;
uniform float size_min : hint_range(0.1, 2.0, 0.05) = 0.62;
uniform float size_max : hint_range(0.1, 2.0, 0.05) = 1.22;
uniform float fade_from : hint_range(0.0, 1.0, 0.01) = 0.88;
uniform bool velocity_stretch_enabled = false;
uniform float stretch_speed_start : hint_range(0.0, 12.0, 0.1) = 4.0;
uniform float stretch_speed_full : hint_range(0.0, 12.0, 0.1) = 7.0;
uniform float stretch_max : hint_range(1.0, 4.0, 0.05) = 1.90;

uint hfn_hash(uint x) {
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = (x >> uint(16)) ^ x;
	return x;
}

float hfn_rand(inout uint seed) {
	int k;
	int s = int(seed);
	if (s == 0) {
		s = 305420679;
	}
	k = s / 127773;
	s = 16807 * (s - k * 127773) - 2836 * k;
	if (s < 0) {
		s += 2147483647;
	}
	seed = uint(s);
	return float(seed % uint(65536)) / 65535.0;
}

void start() {
	uint seed = hfn_hash(NUMBER + uint(1) + RANDOM_SEED);

	if (RESTART_ROT_SCALE) {
		float size = mix(size_min, size_max, hfn_rand(seed));
		CUSTOM.x = size;
		CUSTOM.y = mix(0.92, 1.05, hfn_rand(seed));
		CUSTOM.z = 1.0;
		TRANSFORM[0].xyz = vec3(size, 0.0, 0.0);
		TRANSFORM[1].xyz = vec3(0.0, size, 0.0);
		TRANSFORM[2].xyz = vec3(0.0, 0.0, size);
	}

	if (RESTART_POSITION) {
		vec3 p = vec3(
			(hfn_rand(seed) - 0.5) * box_emit_size.x,
			(hfn_rand(seed) - 0.5) * box_emit_size.y,
			(hfn_rand(seed) - 0.5) * box_emit_size.z
		);
		TRANSFORM[3].xyz = p;
		TRANSFORM = EMISSION_TRANSFORM * TRANSFORM;
	}

	if (RESTART_VELOCITY) {
		USERDATA1 = vec4(
			0.0,
			mix(fall_speed_min, fall_speed_max, hfn_rand(seed)),
			hfn_rand(seed) * TAU,
			hfn_rand(seed) * TAU
		);
		vec3 initial_flutter = vec3(
			(hfn_rand(seed) - 0.5) * 0.35,
			0.0,
			(hfn_rand(seed) - 0.5) * 0.35
		);
		VELOCITY = wind_velocity * 0.15 + initial_flutter;
		VELOCITY.y = -USERDATA1.y;
	}

	USERDATA2 = vec4(TRANSFORM[3].xyz, 1.0);
	if (RESTART_COLOR) {
		COLOR = color;
	}
}

void process() {
	// Particle colliders are the weather-VFX contact authority. Snow does not
	// bounce or rest on the floor: it disappears on first contact.
	if (COLLIDED || snow_door_hit(USERDATA2.xyz, TRANSFORM[3].xyz)
		|| snow_door_hit(TRANSFORM[3].xyz, TRANSFORM[3].xyz + VELOCITY * DELTA)) {
		ACTIVE = false;
	} else {
		USERDATA2 = vec4(TRANSFORM[3].xyz, 1.0);
		USERDATA1.x += DELTA;
		float normalized_age = clamp(USERDATA1.x / max(LIFETIME, 0.001), 0.0, 1.0);

		float flutter_x = sin(TIME * 2.3 + USERDATA1.z) * turbulence_strength;
		float flutter_z = cos(TIME * 1.9 + USERDATA1.w) * turbulence_strength;
		float flutter_y = sin(TIME * 2.7 + USERDATA1.z + USERDATA1.w)
			* turbulence_strength * 0.10;

		// wind_velocity is a live uniform updated every WeatherController tick.
		// This deliberately steers particles that are already airborne.
		vec3 target_velocity = wind_velocity + vec3(
			flutter_x,
			-USERDATA1.y + flutter_y,
			flutter_z
		);
		float response = clamp(1.0 - exp(-drag * DELTA), 0.0, 1.0);
		VELOCITY = mix(VELOCITY, target_velocity, response);

		// Render-only high-wind streak. CUSTOM.z is consumed by the WorldSnow
		// draw shader, so collision scale stays constant.
		float stretch = 1.0;
		if (velocity_stretch_enabled) {
			float speed_factor = smoothstep(
				stretch_speed_start,
				max(stretch_speed_full, stretch_speed_start + 0.01),
				length(VELOCITY)
			);
			stretch = mix(1.0, stretch_max * CUSTOM.y, speed_factor);
		}
		CUSTOM.z = stretch;

		COLOR.a = color.a * (1.0 - smoothstep(fade_from, 1.0, normalized_age));
	}
}
