// Frost on a window pane: grows in from the pane edges (UV 0..1) as coverage rises, with a band
// of crystals at the growth front. Ported from the GDExtension frost lab (hoarbound_frost_controller).

float frost_hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float frost_value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = frost_hash21(i);
	float b = frost_hash21(i + vec2(1.0, 0.0));
	float c = frost_hash21(i + vec2(0.0, 1.0));
	float d = frost_hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float frost_fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	mat2 rot = mat2(vec2(0.80, -0.60), vec2(0.60, 0.80));
	for (int i = 0; i < 5; i++) {
		sum += frost_value_noise(p) * amp;
		p = rot * p * 2.03 + vec2(13.7, 9.2);
		amp *= 0.5;
	}
	return sum;
}

// x = frost cover of this texel (0 clear glass, 1 frosted), y = crystal vein at the growth front.
// `seed` shifts the pattern so neighbouring panes do not repeat.
vec2 frost_pattern(vec2 uv, float coverage, float seed) {
	vec2 p = uv + vec2(seed * 7.13, seed * 3.71);
	float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	float broad = frost_fbm(p * vec2(5.5, 4.2));
	float fine = frost_value_noise(p * vec2(36.0, 28.0));
	float reach = mix(-0.085, 0.565, coverage);
	float noisy_edge = edge + (broad - 0.5) * 0.105 + (fine - 0.5) * 0.022;
	float frost = 1.0 - smoothstep(reach - 0.055, reach + 0.020, noisy_edge);
	frost *= smoothstep(0.0, 0.035, coverage);
	float front_band = 1.0 - smoothstep(0.015, 0.090, abs(noisy_edge - reach));
	float crystals = smoothstep(0.68, 0.92, frost_value_noise(p * 74.0 + broad * 7.0));
	return vec2(frost, front_band * crystals * frost);
}

// Pane colour for a frost result; fully frosted panes keep a faint fern grain instead of a flat fill.
vec3 frost_color(vec2 uv, vec2 f, vec3 glass_tint, vec3 frost_tint) {
	vec3 base = mix(glass_tint, frost_tint, f.x);
	base *= mix(1.0, 0.92 + 0.08 * frost_fbm(uv * 9.0), f.x);
	return mix(base, vec3(1.0), f.y * 0.52);
}
