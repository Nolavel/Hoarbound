// Window frost from two baked tiles at 1 mm per pixel (tools/textures/bake_window_frost_sheet.py), laid in
// metres so a pane of any size or proportion carries crystals of true size. Include after
// frost_pattern.gdshaderinc: this uses its hash, noise and pane-size helpers.
//
// The tiles are project shader globals, so every baked scene that uses a window shader gets them unbound.
// Both: R crystal lines, G hoar grains, A smooth thickness. The strip tiles along x, frame on its bottom row.
global uniform sampler2D window_frost_edge : repeat_enable, filter_linear_mipmap;
global uniform sampler2D window_frost_field : repeat_enable, filter_linear_mipmap;

const vec2 FROST_STRIP_M = vec2(1.024, 0.384);
const float FROST_FIELD_M = 1.024;

// The feather strip along one edge: `along` the edge and `dist` in from it, metres, at uniform `scale`.
vec4 frost_strip(float along, float dist, float scale, float offset) {
	// The band is not one depth all along an edge: it swells and thins every half metre or so.
	float depth = scale * mix(0.35, 1.25, frost_value_noise(vec2(along * 2.3 + offset * 9.0, offset * 4.0)));
	float v = dist / (FROST_STRIP_M.y * depth);
	vec4 s = texture(window_frost_edge, vec2((along / scale + offset) / FROST_STRIP_M.x, 1.0 - clamp(v, 0.001, 1.0)));
	return s * step(v, 0.97);
}

// When frost reaches a texel: 0 at the frame, 1 some 40 cm in (so a small pane frosts right across), deeper
// off the sill, uneven all round.
float frost_order(vec2 m, vec2 pane, float seed) {
	float side = min(m.x, pane.x - m.x) * 1.1;
	float bottom = (pane.y - m.y) * 0.75;
	float top = m.y * 1.6;
	// A soft minimum rounds the corners instead of mitring them.
	float k = 0.05;
	float rank = clamp(-k * log(exp(-side / k) + exp(-bottom / k) + exp(-top / k)) / 0.40, 0.0, 1.0);
	return clamp(rank * 1.05 + (frost_value_noise(m * 1.9 + seed * 5.3) - 0.5) * 0.75
		+ (frost_value_noise(m * 8.0 + seed) - 0.5) * 0.16, 0.0, 1.0);
}

// How far a pane is frosted right across: 0 up to 80 % coverage, 1 at full coverage (a house with nothing inside).
float frost_fill(float coverage) {
	return smoothstep(0.8, 1.0, coverage);
}

// Crystal lines, hoar and smooth thickness at `m` metres on a pane of `pane` metres. `order` from frost_order;
// `fill` from frost_fill packs the middle with crystals too.
vec3 frost_at(vec2 m, vec2 pane, float seed, float order, float fill) {
	// A small pane takes smaller feathers, so two edges never swallow it whole.
	float k = clamp(min(pane.x, pane.y) / 0.9, 0.45, 1.0);
	float o = seed * 3.7;
	// The sill grows the longest feathers, the head of the pane the shortest.
	vec4 e = frost_strip(m.x, pane.y - m.y, k, o);
	e = max(e, frost_strip(m.y, m.x, k * 0.8, o + 0.31));
	e = max(e, frost_strip(pane.y - m.y, pane.x - m.x, k * 0.8, o + 0.67));
	e = max(e, frost_strip(pane.x - m.x, m.y, k * 0.55, o + 0.13));
	// Free crystals keep to the colder glass; the warm middle of a large pane carries almost none.
	vec2 p = m + vec2(seed * 3.1, seed * 1.7);
	vec4 f = texture(window_frost_field, p / FROST_FIELD_M) * (1.0 - smoothstep(0.45, 0.85, order) * 0.9 * (1.0 - fill));
	// A pane frosted right across: two more layers of crystals, turned and at their own scale, with no gaps.
	// Gradients are taken outside the branch, where they are defined.
	vec2 gu = vec2(-p.y, p.x) / (FROST_FIELD_M * 0.83) + 0.37;
	vec2 hu = (p + vec2(p.y, -p.x) * 0.35) / (FROST_FIELD_M * 0.61) + 0.71;
	vec2 gdx = dFdx(gu);
	vec2 gdy = dFdy(gu);
	vec2 hdx = dFdx(hu);
	vec2 hdy = dFdy(hu);
	if (fill > 0.0) {
		f = max(f, max(textureGrad(window_frost_field, gu, gdx, gdy), textureGrad(window_frost_field, hu, hdx, hdy)) * fill);
	}
	return max(e.rga, f.rga);
}

// The frost on a pane before any thaw: x crystal lines, y hoar, z smooth thickness, w the film under them.
// `coverage` 0..1 is how much of the pane frost has reached; at 1 it is frosted right across.
vec4 frost_cover(vec2 m, vec2 pane, float coverage, float seed, float order) {
	float fill = frost_fill(coverage);
	vec3 crystals = frost_at(m, pane, seed, order, fill);
	float reach = coverage * 1.35;
	float present = (1.0 - smoothstep(reach - 0.22, reach, order)) * smoothstep(0.0, 0.25, coverage);
	float grain = 0.75 + 0.5 * frost_value_noise(m * 14.0 + seed * 9.0);
	// A breath-thin film that thickens to the frame; right across the pane it is a full coat.
	float film = present * mix(mix(0.34, 0.07, smoothstep(0.10, 0.70, order)), 1.05, fill) * grain;
	return vec4(crystals * present, film);
}
