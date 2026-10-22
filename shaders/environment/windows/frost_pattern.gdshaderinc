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

// Pane size in metres from screen derivatives (a pane's UV is affine on it), so the pattern keeps
// its scale on wide and tall panes. Call from fragment(); `vertex` is any space in metres.
vec2 frost_pane_m(vec2 uv, vec3 vertex) {
	mat2 j = mat2(dFdx(uv), dFdy(uv));
	if (abs(determinant(j)) < 1e-12) {
		return vec2(1.0);
	}
	mat2 ji = inverse(j);
	vec3 du = dFdx(vertex) * ji[0].x + dFdy(vertex) * ji[0].y;
	vec3 dv = dFdx(vertex) * ji[1].x + dFdy(vertex) * ji[1].y;
	return clamp(vec2(length(du), length(dv)), vec2(0.05), vec2(6.0));
}

// Glass temperature rank: 0 on the coldest edge, rising to ~1 in the warm centre. Metric, so a
// band is as deep on a wide pane's sides as on a tall pane's.
float frost_cold_rank(vec2 m, vec2 pane) {
	float half_min = 0.5 * min(pane.x, pane.y);
	float side = min(m.x, pane.x - m.x) / half_min * 1.1;
	float bottom = (pane.y - m.y) / half_min * 0.75;
	float top = m.y / half_min * 1.6;
	// A soft minimum rounds the corners instead of mitring them.
	float k = 0.12;
	float d = -k * log(exp(-side / k) + exp(-bottom / k) + exp(-top / k));
	return clamp(d, 0.0, 1.2);
}

// How far the frost reaches in from the frame here, 0 hugging it to 1 tongued towards the centre:
// noise round the pane's rim (seamless in angle) with a little broad noise across it.
float frost_reach(vec2 uv, vec2 m, float seed) {
	vec2 r = uv - 0.5;
	float a = atan(r.y, r.x);
	float rim = frost_fbm(vec2(cos(a), sin(a)) * 1.3 + vec2(seed * 5.1, seed * 2.3));
	float across = frost_fbm(m * 2.5 + seed * 9.7);
	return clamp((rim * 0.75 + across * 0.25 - 0.5) * 3.2 + 0.5, 0.0, 1.0);
}

// Distance in metres to the nearest scratch that nucleates frost (few 0.3 m cells hold one).
float frost_nucleus(vec2 m, float seed) {
	vec2 cell = m / 0.3;
	vec2 base = floor(cell);
	float best = 9.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = base + vec2(float(x), float(y));
			float h = frost_hash21(c + seed * 17.0);
			if (h > 0.72) {
				vec2 at = c + vec2(frost_hash21(c + 3.1 + seed), frost_hash21(c + 7.7 + seed));
				best = min(best, length(cell - at) * 0.3);
			}
		}
	}
	return best;
}

// One layer of fern fronds seeded per `cell_m` cell: a tapering spine leaning along the growth
// direction `g` (freer the further from the frame), barbs at 60 degrees towards its tip.
float frost_fronds(vec2 m, float cell_m, vec2 g, float freedom, float seed) {
	vec2 cell = m / cell_m;
	// Pixel footprint in cells: barbs a pixel cannot hold blend to their mean; lines stay a pixel wide.
	float px = length(fwidth(cell));
	float barb_detail = 1.0 - smoothstep(0.03, 0.07, px);
	float line_w = max(0.012, px * 0.6);
	vec2 base = floor(cell);
	float best = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = base + vec2(float(x), float(y));
			float h = frost_hash21(c + seed * 31.0);
			vec2 origin = c + vec2(frost_hash21(c + 1.3 + seed), frost_hash21(c + 8.9 + seed));
			float a = (h - 0.5) * mix(1.6, 6.2, freedom);
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
			float spine = 1.0 - smoothstep(line_w, line_w * 3.0, abs(t));
			float barb_line = abs(2.0 * fract((s - abs(t) * 0.577) * 11.0 + h * 5.0) - 1.0);
			float barb = mix(0.3, smoothstep(0.55, 0.9, barb_line), barb_detail);
			barb *= 1.0 - smoothstep(half_w * 0.7, half_w, abs(t));
			best = max(best, max(spine, barb * (0.55 + 0.45 * taper)));
		}
	}
	return best;
}

// x = frost opacity (thin new frost is translucent), y = crystal glint at the growth front,
// z = meltwater film behind a thaw front. `thaw` 0..1 clears from the centre outwards.
// `seed` draws the frost; `melt_seed` draws this thaw's path, so each thaw clears differently.
vec3 frost_pattern(vec2 uv, vec2 pane, float coverage, float thaw, float seed, float melt_seed) {
	vec2 m = uv * pane;
	vec2 p = m + vec2(seed * 7.13, seed * 3.71);
	float rank = frost_cold_rank(m, pane);
	// Tongues of frost run far in where the rim is coldest, elsewhere it keeps to the frame.
	float cold = rank * mix(2.1, 0.4, frost_reach(uv, m, seed));
	float nucleus = frost_nucleus(m, seed);
	float e = 0.01;
	vec2 grad = vec2(frost_cold_rank(m + vec2(e, 0.0), pane) - frost_cold_rank(m - vec2(e, 0.0), pane),
		frost_cold_rank(m + vec2(0.0, e), pane) - frost_cold_rank(m - vec2(0.0, e), pane));
	vec2 g = length(grad) > 1e-4 ? normalize(grad) : vec2(0.0, -1.0);
	// Fronds that start far from the frame grow any way: the middle is no rosette.
	float freedom = smoothstep(0.35, 0.85, rank);
	float fern = max(frost_fronds(m, 0.16, g, freedom, seed),
		frost_fronds(m + 0.37, 0.07, g, freedom, seed + 0.5) * 0.75);
	float broad = frost_fbm(p * 5.0);
	// When this texel frosts: edges and scratches first, veins ahead of the glass between them.
	float grow_at = min(clamp(cold, 0.0, 1.0), 0.25 + nucleus * 3.0) * 0.78 + (broad - 0.5) * 0.14 - fern * 0.12 + 0.08;
	float frost = 1.0 - smoothstep(coverage - 0.015, coverage + 0.005, grow_at);
	frost *= smoothstep(0.0, 0.03, coverage);
	float age = clamp((coverage - grow_at) * 5.0, 0.0, 1.0);
	float opacity = frost * mix(0.35, 1.0, age) * mix(0.55, 1.0, fern);
	float front = (1.0 - smoothstep(0.0, 0.04, coverage - grow_at)) * frost;
	float crystals = front * smoothstep(0.55, 0.9, frost_value_noise(p * 160.0 + fern * 4.0));
	// When it clears: the warm centre first (its own rim noise for this thaw), thick veins last.
	vec2 q = m + vec2(melt_seed * 11.3, melt_seed * 4.9);
	float warm_reach = frost_reach(uv, m, melt_seed + 0.71);
	float melt_at = 1.0 - clamp(rank * mix(1.9, 0.6, warm_reach), 0.0, 1.0) + fern * 0.14 + (frost_fbm(q * 3.0) - 0.5) * 0.24;
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
