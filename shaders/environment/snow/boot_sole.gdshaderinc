// Henry's army boot outsole in sole-local uv (x: -1 heel back .. 1 toe, y: -1..1
// across the ball). Mirrors BootSole (scripts/systems/world/snow/boot_sole.gd).

const float BOOT_BREAST_U = -0.44;
const float BOOT_HEEL_HALF = 0.74;
const float BOOT_WAIST_HALF = 0.62;

float boot_half_width(float u) {
	if (u <= -1.0 || u >= 1.0) {
		return 0.0;
	}
	if (u < -0.72) {
		float t = (u + 0.72) / 0.28;
		return BOOT_HEEL_HALF * pow(max(1.0 - t * t * t * t, 0.0), 0.25);
	}
	if (u < BOOT_BREAST_U) {
		return BOOT_HEEL_HALF;
	}
	if (u < 0.42) {
		float waist = mix(0.7, BOOT_WAIST_HALF, smoothstep(BOOT_BREAST_U, -0.2, u));
		return mix(waist, 1.0, smoothstep(-0.2, 0.42, u));
	}
	if (u < 0.55) {
		return 1.0;
	}
	float toe = (u - 0.55) / 0.45;
	return sqrt(max(1.0 - toe * toe, 0.0));
}

// Share of the boot's press: heel block and ball full, the arched shank light.
float boot_press(float u) {
	float shank = smoothstep(BOOT_BREAST_U - 0.02, BOOT_BREAST_U + 0.02, u) * (1.0 - smoothstep(-0.05, 0.2, u));
	return mix(1.0, 0.45, shank) * mix(1.0, 0.85, smoothstep(0.6, 1.0, u));
}

// Approximate distance to the outsole edge in metres, negative inside.
float boot_edge_m(vec2 uv, vec2 half_m) {
	float w = boot_half_width(clamp(uv.x, -0.999, 0.999));
	float side = (abs(uv.y) - w) * half_m.y;
	float end = (abs(uv.x) - 1.0) * half_m.x;
	return abs(uv.x) < 1.0 ? max(side, end) : max(end, abs(uv.y) * half_m.y - BOOT_HEEL_HALF * half_m.y);
}

// 1 on a lug, 0 in a groove: chevrons pointing to the toe on the forefoot, transverse
// bars on the heel block, a smooth shank, a centre channel and a lugged rim.
float boot_lug(vec2 uv, vec2 half_m) {
	vec2 m = uv * half_m;
	float edge = -boot_edge_m(uv, half_m);
	float channel = smoothstep(0.003, 0.005, abs(m.y));
	float rim = 1.0 - smoothstep(0.006, 0.008, edge);
	if (uv.x < BOOT_BREAST_U) {
		float bar = fract(m.x / 0.017);
		return max(smoothstep(0.15, 0.25, bar) * (1.0 - smoothstep(0.65, 0.75, bar)) * channel, rim);
	}
	if (uv.x < 0.05) {
		return 0.0;
	}
	float chevron = fract((m.x - abs(m.y) * 0.7) / 0.018);
	return max(smoothstep(0.15, 0.25, chevron) * (1.0 - smoothstep(0.6, 0.7, chevron)) * channel, rim);
}
