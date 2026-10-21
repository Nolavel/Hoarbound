// Frost on a window pane (UV 0..1, v = 1 at the bottom) as two dissolve masks: when a texel frosts
// (bottom edge, sides, scratches; fern veins lead) and when it clears (warm centre first).

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

// Glass temperature rank: 0 on the coldest edge, rising to ~1 in the warm centre.
float frost_cold_rank(vec2 uv) {
	float side = min(uv.x, 1.0 - uv.x) * 2.2;
	float bottom = (1.0 - uv.y) * 1.5;
	float top = uv.y * 3.2;
	// A soft minimum rounds the corners instead of mitring them.
	float k = 0.12;
	float d = -k * log(exp(-side / k) + exp(-bottom / k) + exp(-top / k));
	return clamp(d, 0.0, 1.2);
}

// Distance to the nearest scratch that nucleates frost on this pane (few cells hold one).
float frost_nucleus(vec2 uv, float seed) {
	vec2 cell = uv * vec2(3.0, 4.0);
	vec2 base = floor(cell);
	float best = 9.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = base + vec2(float(x), float(y));
			float h = frost_hash21(c + seed * 17.0);
			if (h > 0.72) {
				vec2 at = c + vec2(frost_hash21(c + 3.1 + seed), frost_hash21(c + 7.7 + seed));
				best = min(best, length((cell - at) / vec2(3.0, 4.0)));
			}
		}
	}
	return best;
}

// One layer of fern fronds seeded per cell: a tapering spine leaning along the growth direction
// `g`, dense barbs at 60 degrees towards its tip. 1 on ice, 0 between fronds.
float frost_fronds(vec2 uv, vec2 cells, vec2 g, float seed) {
	vec2 cell = uv * cells;
	vec2 base = floor(cell);
	float best = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = base + vec2(float(x), float(y));
			float h = frost_hash21(c + seed * 31.0);
			vec2 origin = c + vec2(frost_hash21(c + 1.3 + seed), frost_hash21(c + 8.9 + seed));
			float a = (h - 0.5) * 1.6;
			vec2 dir = vec2(g.x * cos(a) - g.y * sin(a), g.x * sin(a) + g.y * cos(a));
			vec2 local = cell - origin;
			float s = dot(local, dir);
			float t = dot(local, vec2(-dir.y, dir.x));
			float len = 1.1 + h * 0.9;
			if (s < 0.0 || s > len) {
				continue;
			}
			float taper = 1.0 - s / len;
			float half_w = 0.06 + 0.42 * taper * smoothstep(0.0, 0.25, s);
			float spine = 1.0 - smoothstep(0.012, 0.04, abs(t));
			float barb_line = abs(2.0 * fract((s - abs(t) * 0.577) * 11.0 + h * 5.0) - 1.0);
			float barb = smoothstep(0.55, 0.9, barb_line) * (1.0 - smoothstep(half_w * 0.7, half_w, abs(t)));
			best = max(best, max(spine, barb * (0.55 + 0.45 * taper)));
		}
	}
	return best;
}

// x = frost opacity (thin new frost is translucent), y = crystal glint at the growth front,
// z = meltwater film behind a thaw front. `thaw` 0..1 clears from the centre outwards.
vec3 frost_pattern(vec2 uv, float coverage, float thaw, float seed) {
	vec2 p = uv + vec2(seed * 7.13, seed * 3.71);
	float cold = frost_cold_rank(uv);
	float nucleus = frost_nucleus(uv, seed);
	float e = 0.01;
	vec2 grad = vec2(frost_cold_rank(uv + vec2(e, 0.0)) - frost_cold_rank(uv - vec2(e, 0.0)),
		frost_cold_rank(uv + vec2(0.0, e)) - frost_cold_rank(uv - vec2(0.0, e)));
	vec2 g = length(grad) > 1e-4 ? normalize(grad) : vec2(0.0, -1.0);
	float fern = max(frost_fronds(uv, vec2(4.0, 5.5), g, seed), frost_fronds(uv + 0.37, vec2(9.0, 12.0), g, seed + 0.5) * 0.75);
	float broad = frost_fbm(p * vec2(4.0, 3.0));
	// When this texel frosts: edges and scratches first, veins ahead of the glass between them.
	float grow_at = min(clamp(cold, 0.0, 1.0), 0.25 + nucleus * 1.8) * 0.78 + (broad - 0.5) * 0.14 - fern * 0.12 + 0.08;
	float frost = 1.0 - smoothstep(coverage - 0.015, coverage + 0.005, grow_at);
	frost *= smoothstep(0.0, 0.03, coverage);
	float age = clamp((coverage - grow_at) * 5.0, 0.0, 1.0);
	float opacity = frost * mix(0.35, 1.0, age) * mix(0.55, 1.0, fern);
	float front = (1.0 - smoothstep(0.0, 0.04, coverage - grow_at)) * frost;
	float crystals = front * smoothstep(0.55, 0.9, frost_value_noise(p * 90.0 + fern * 4.0));
	// When it clears: the warm centre first, thick veins and the cold bottom corners last.
	float melt_at = 1.0 - clamp(cold * 1.15, 0.0, 1.0) + fern * 0.14 + (frost_fbm(p * 2.2) - 0.5) * 0.2;
	float clear_at = mix(-0.3, 1.2, thaw);
	float left = smoothstep(clear_at - 0.07, clear_at + 0.03, melt_at);
	float thinning = mix(1.0, smoothstep(clear_at - 0.07, clear_at + 0.3, melt_at), step(0.001, thaw));
	float wet = step(0.001, thaw) * frost * (1.0 - left) * (1.0 - smoothstep(0.0, 0.14, clear_at - melt_at));
	return vec3(opacity * left * thinning, crystals * left, wet);
}

// Pane colour for a frost result: frost over the glass, a fern grain, glints at a growing front.
vec3 frost_color(vec2 uv, vec3 f, vec3 glass_tint, vec3 frost_tint) {
	vec3 base = mix(glass_tint, frost_tint, f.x);
	base *= mix(1.0, 0.92 + 0.08 * frost_fbm(uv * 9.0), f.x);
	return mix(base, vec3(1.0), f.y * 0.52);
}
