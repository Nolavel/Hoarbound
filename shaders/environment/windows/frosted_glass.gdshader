// See-through glass in real window openings (authored buildings such as 727 Fort St). Per vertex:
// COLOR.r = the pane's frost coverage in the cold, COLOR.g = 1 for a heated room, COLOR.b = seed.
// Warmth of the two rooms comes from the shelter's thermal zones; a warmed room clears to about warm_coverage.
//
// The frost is two baked tiles at 1 mm per pixel (tools/textures/bake_window_frost_sheet.py), laid in metres:
// a strip of fern feathers along each edge of the pane and a field of small crystals across it, so a pane of
// any size and proportion carries crystals of true size. It thaws by local need: soaks to glassy ice, sheds
// plates that slide to the sill, breaks up and clears; the wet pane mists with beads and sheds thin short runs.
// No screen read: snowfall and other transparents behind the pane stay visible.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_prepass_alpha;

// Only its hash, noise, pane-size and cold-rank helpers are used here.
#include "res://shaders/environment/windows/frost_pattern.gdshaderinc"

uniform vec4 frost_tint : source_color = vec4(0.965, 0.970, 0.972, 1.0);
uniform vec4 hoar_tint : source_color = vec4(0.80, 0.85, 0.90, 1.0);
uniform vec4 wet_ice_tint : source_color = vec4(0.60, 0.68, 0.74, 1.0);
uniform vec4 glass_tint : source_color = vec4(0.62, 0.76, 0.86, 1.0);
uniform float heated_warmth : hint_range(0.0, 1.0) = 0.0;
uniform float unheated_warmth : hint_range(0.0, 1.0) = 0.0;
uniform float warm_coverage : hint_range(0.0, 1.0) = 0.2;
// Drawn afresh each world load (the frost) and each time the room starts to warm (the thaw's path).
uniform float growth_seed = 0.0;
uniform float melt_seed = 0.0;
// R crystal lines, G hoar grains, A smooth thickness. The strip tiles along x with the frame on its bottom row.
uniform sampler2D frost_edge : hint_default_black, repeat_enable, filter_linear_mipmap;
uniform sampler2D frost_field : hint_default_black, repeat_enable, filter_linear_mipmap;

const vec2 STRIP_M = vec2(1.024, 0.384);
const float FIELD_M = 1.024;
const float RUN_GAP_M = 0.043;
const float PLATE_GAP_M = 0.11;

// The feather strip along one edge: `along` the edge and `dist` in from it, metres, at uniform `scale`.
vec4 frost_strip(float along, float dist, float scale, float offset) {
	// The band is not one depth all along an edge: it swells and thins every half metre or so.
	float depth = scale * mix(0.35, 1.25, frost_value_noise(vec2(along * 2.3 + offset * 9.0, offset * 4.0)));
	float v = dist / (STRIP_M.y * depth);
	vec4 s = texture(frost_edge, vec2((along / scale + offset) / STRIP_M.x, 1.0 - clamp(v, 0.001, 1.0)));
	return s * step(v, 0.97);
}

// Crystal lines, hoar and smooth thickness at `m` metres on a pane of `pane` metres.
vec3 frost_at(vec2 m, vec2 pane, float seed, float order) {
	// A small pane takes smaller feathers, so two edges never swallow it whole.
	float k = clamp(min(pane.x, pane.y) / 0.9, 0.45, 1.0);
	float o = seed * 3.7;
	// The sill grows the longest feathers, the head of the pane the shortest.
	vec4 e = frost_strip(m.x, pane.y - m.y, k, o);
	e = max(e, frost_strip(m.y, m.x, k * 0.8, o + 0.31));
	e = max(e, frost_strip(pane.y - m.y, pane.x - m.x, k * 0.8, o + 0.67));
	e = max(e, frost_strip(pane.x - m.x, m.y, k * 0.55, o + 0.13));
	// Free crystals keep to the colder glass; the warm middle of a large pane carries almost none.
	vec4 f = texture(frost_field, (m + vec2(seed * 3.1, seed * 1.7)) / FIELD_M) * (1.0 - smoothstep(0.45, 0.85, order) * 0.9);
	return max(e.rga, f.rga);
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

// Warmth a texel needs before it starts to thaw: frost by the frame and low on the pane holds out longer.
float thaw_need(vec2 m, vec2 pane, float order, float seed) {
	vec2 uv = m / pane;
	float lobes = frost_value_noise(m * 1.3 + seed * 7.1) * 0.65 + frost_value_noise(m * 3.4 + seed * 3.3) * 0.35 - 0.5;
	float away = clamp(length((uv - vec2(0.5, 0.42)) * vec2(pane.x / pane.y, 1.0)) / 0.95, 0.0, 1.0);
	float by_frame = 1.0 - order;
	// Warm air rises along the glass: the upper pane leads, the sill lags.
	return 0.06 + 0.30 * by_frame * by_frame + 0.14 * away + 0.30 * uv.y * uv.y + lobes * 0.44;
}

// One layer of water beads scattered over a `cell_m` grid: xy = lens normal, z = bead mask, w = highlight.
vec4 frost_beads(vec2 m, float cell_m, float seed, float grow, float density) {
	vec2 c = m / cell_m;
	vec2 base = floor(c);
	// Beads a pixel cannot hold fade out instead of shimmering.
	float px = length(fwidth(c));
	vec4 best = vec4(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 id = base + vec2(float(x), float(y));
			if (frost_hash21(id + seed * 13.7) > density) {
				continue;
			}
			vec2 centre = id + vec2(frost_hash21(id + 1.7 + seed), frost_hash21(id + 5.3 + seed));
			float r = mix(0.10, 0.34, pow(frost_hash21(id + 9.1 + seed), 2.0)) * grow;
			vec2 d = c - centre;
			d.y *= 0.86;  // a bead sags a little under its own weight
			float q = length(d) / max(r, 1e-4);
			float mask = (1.0 - smoothstep(0.82, 1.0, q)) * (1.0 - smoothstep(r * 0.9, r * 2.2, px));
			if (mask > best.z) {
				vec2 n = d / max(r, 1e-4);
				float glint = 1.0 - smoothstep(0.0, 0.34, length(n - vec2(-0.34, -0.42)));
				best = vec4(n * mask, mask, glint * mask);
			}
		}
	}
	return best;
}

// An ice plate's outline round `p` (metres from its middle): a shard with five straight uneven sides, wider
// than tall. Returns 1 inside, falling to 0 over the last `soft` metres.
float frost_plate(vec2 p, float r, float id, float soft) {
	vec2 q = p / vec2(1.45, 1.0);
	float d = -1.0;
	for (int k = 0; k < 5; k++) {
		float fk = float(k);
		float a = 1.2566 * (fk + 0.7 * frost_hash21(vec2(id + fk * 3.1, 2.7))) + id;
		d = max(d, dot(q, vec2(cos(a), sin(a))) - r * mix(0.55, 1.0, frost_hash21(vec2(id * 1.7 + fk, 8.3))));
	}
	d += (frost_value_noise(p * 260.0 + id) - 0.5) * 0.003;  // a broken edge is never dead straight
	return 1.0 - smoothstep(-soft, 0.0, d);
}

// Lays a layer of colour `lc` and opacity `la` over what is already there.
void frost_over(inout vec3 c, inout float a, vec3 lc, float la) {
	float na = la + a * (1.0 - la);
	c = (lc * la + c * a * (1.0 - la)) / max(na, 1e-4);
	a = na;
}

void fragment() {
	vec2 pane = frost_pane_m(UV, VERTEX);
	vec2 m = UV * pane;
	float warmth = COLOR.g > 0.5 ? heated_warmth : unheated_warmth;
	float t = warmth * (1.0 - warm_coverage * 0.4);
	float seed = COLOR.b + growth_seed;
	float thaw_seed = COLOR.b + melt_seed;

	// --- the frost: feathers and hoar over a breath-thin film that thickens to the frame
	float order = frost_order(m, pane, seed);
	vec3 crystals = frost_at(m, pane, seed, order);
	float reach = COLOR.r * 1.35;
	float present = (1.0 - smoothstep(reach - 0.22, reach, order)) * smoothstep(0.0, 0.25, COLOR.r);
	float lines = crystals.x * present;
	float hoar = crystals.y * present;
	float body = crystals.z * present;
	float film = present * mix(0.34, 0.07, smoothstep(0.10, 0.70, order))
		* (0.75 + 0.5 * frost_value_noise(m * 14.0 + seed * 9.0));
	float thick = lines * 0.95 + hoar * 0.42 + film;

	// --- when this texel thaws
	float need = thaw_need(m, pane, order, thaw_seed) + body * 0.20 + lines * 0.05
		+ (frost_value_noise(m * 90.0 + thaw_seed * 5.0) - 0.5) * 0.04;
	float s = (t - need) / 0.22;  // <0 dry, 0..0.6 soaking, 0.6..1 breaking up, >1 clear

	// --- plates: soaked frost lets go in sheets that slide to the sill and melt there
	float hole = 0.0;
	float plate = 0.0;
	float plate_fade = 0.0;
	vec2 plate_from = m;
	float cell0 = floor(m.x / PLATE_GAP_M);
	for (int i = -1; i <= 1; i++) {
		float cell = cell0 + float(i);
		float h1 = frost_hash21(vec2(cell * 5.3 + thaw_seed * 3.0, 1.7));
		if (h1 > 0.7) {
			continue;
		}
		float h2 = frost_hash21(vec2(cell, 9.4 + thaw_seed));
		float r = mix(0.028, 0.060, frost_hash21(vec2(cell, 4.1 + thaw_seed))) * clamp(pane.y / 0.9, 0.5, 1.0);
		vec2 c0 = vec2((cell + 0.25 + 0.5 * h2) * PLATE_GAP_M, pane.y - mix(0.08, 0.48, h1 / 0.7) * min(pane.y, 1.2));
		float c_order = frost_order(c0, pane, seed);
		// Only frost thick enough to hold together comes away as a plate.
		if (c_order > min(reach - 0.1, 0.5) || c0.x < r || c0.x > pane.x - r) {
			continue;
		}
		// It lets go half way through soaking, creeps, then slides.
		float tau = clamp((t - thaw_need(c0, pane, c_order, thaw_seed) - 0.10) / 0.20, 0.0, 1.0);
		if (tau <= 0.0) {
			continue;
		}
		float fall = (pane.y - c0.y - r * 0.5) * pow(smoothstep(0.0, 0.72, tau), 1.7);
		float melt = 1.0 - smoothstep(0.72, 1.0, tau);  // on the sill it shrinks and goes
		// What it leaves behind is a ragged thin patch, not a cut-out of its outline.
		hole = max(hole, frost_plate(m - c0, r * 1.1, cell, r * 0.6) * 0.8);
		float here = frost_plate(m - c0 - vec2(0.0, fall), r * mix(0.55, 1.0, melt), cell, 0.002);
		if (here > plate) {
			plate = here;
			plate_fade = melt;
			plate_from = m - vec2(0.0, fall);
		}
	}
	vec3 carried = frost_at(plate_from, pane, seed, frost_order(plate_from, pane, seed));

	// --- runs: thin and short. A bead gathers where the frost soaks, creeps, lets go, and stops as a
	// hanging drop unless it reaches the sill.
	float track = 0.0;
	float track_wet = 0.0;
	float water = 0.0;
	vec2 water_n = vec2(0.0);
	float water_glint = 0.0;
	float lane0 = floor(m.x / RUN_GAP_M);
	float px = fwidth(m.x);
	for (int i = -1; i <= 1; i++) {
		float lane = lane0 + float(i);
		float h = frost_hash21(vec2(lane * 3.71 + thaw_seed * 9.0, 6.13));
		float x0 = (lane + 0.1 + 0.8 * frost_hash21(vec2(lane, 2.9 + thaw_seed))) * RUN_GAP_M;
		float y0 = mix(0.18, 0.93, frost_hash21(vec2(lane, 7.91 + thaw_seed))) * pane.y;
		vec2 start = vec2(x0, y0);
		float phase = clamp((t - thaw_need(start, pane, frost_order(start, pane, seed), thaw_seed) - 0.05) * mix(2.2, 4.0, h), 0.0, 1.0);
		if (phase <= 0.0 || m.y < y0 - 0.01) {
			continue;
		}
		float head = min(y0 + mix(0.05, 0.34, h * h) * phase * phase, pane.y);
		float wander = (frost_value_noise(vec2(m.y * 14.0 + lane * 3.3, h * 9.2)) - 0.5) * 0.012
			+ (frost_value_noise(vec2(m.y * 60.0 + lane * 1.7, 4.4)) - 0.5) * 0.003;
		float dx = m.x - (x0 + wander);
		float half_w = mix(0.0009, 0.0021, h);
		// A line a pixel cannot hold keeps a pixel's width and fades instead.
		float draw_w = max(half_w, px * 0.6);
		float fade = clamp(half_w / draw_w, 0.25, 1.0);
		float in_len = smoothstep(y0 - 0.003, y0 + 0.006, m.y) * (1.0 - smoothstep(head - 0.002, head + 0.002, m.y));
		track = max(track, (1.0 - smoothstep(draw_w * 0.9, draw_w * 1.5, abs(dx))) * in_len * fade);
		track_wet = max(track_wet, (1.0 - smoothstep(draw_w * 1.2, draw_w * 2.6, abs(dx))) * in_len * fade);
		float behind = head - m.y;
		float broken = mix(1.0, smoothstep(0.40, 0.62, frost_value_noise(vec2(m.y * 260.0 + lane * 9.0, h * 3.0))),
			smoothstep(0.01, 0.06, behind));
		float thread = (1.0 - smoothstep(draw_w * 0.5, draw_w, abs(dx))) * in_len * broken * fade;
		vec2 tip = vec2(dx, m.y - head + 0.0015);
		tip.y *= tip.y < 0.0 ? 0.5 : 1.0;  // teardrop: long above, round below
		float head_r = max(half_w * 1.7, px * 0.9);
		float bead = (1.0 - smoothstep(0.7, 1.0, length(tip) / head_r)) * clamp(half_w * 1.7 / head_r, 0.35, 1.0);
		float here = max(thread, bead);
		if (here > water) {
			water = here;
			water_n = bead > thread ? tip / head_r : vec2(dx / draw_w, 0.0);
			water_glint = 1.0 - smoothstep(0.0, 0.45, length(water_n - vec2(-0.36, bead > thread ? -0.40 : 0.0)));
		}
	}

	// --- what is left of the frost
	float soak = max(smoothstep(-0.15, 0.6, s), track_wet * 0.55);
	// It does not fade: it breaks into slush islands that shrink.
	float islands = frost_fbm(m * 30.0 + thaw_seed * 23.0) * 0.6 + frost_value_noise(m * 120.0 + 8.3) * 0.4;
	float left = 1.0 - smoothstep(0.0, 1.0, (s - 0.6) * 2.5 - (islands - 0.5) * 1.6);
	left *= (1.0 - track * 0.9) * (1.0 - hole);
	// Soaking fuses grains and feathers into one sheet of clear ice before it goes.
	float fused = mix(thick, body * 0.75 + film, soak * 0.7);
	float body_thick = fused * left * mix(1.0, 0.6, soak);
	float scatter = 1.0 - exp(-body_thick * mix(2.7, 1.1, soak));

	// --- mist and beads on wet glass
	float open = clamp(1.0 - left, 0.0, 1.0) * smoothstep(0.02, 0.2, t) * present;
	float damp = max(open, soak * 0.8 * present) * smoothstep(0.03, 0.25, t);
	float fresh = 1.0 - smoothstep(1.2, 4.5, s);  // it dries in the end
	vec4 mist = frost_beads(m, 0.0052, thaw_seed + 0.4, damp * fresh, 0.72);
	vec4 big = frost_beads(m + 0.37, 0.016, thaw_seed, open * mix(0.5, 1.0, fresh), 0.34 * mix(0.3, 1.0, fresh));
	// Too far to see single drops, mist reads as a faint veil instead of shimmering.
	float veil = damp * fresh * (0.55 + 0.45 * frost_value_noise(m * 26.0 + thaw_seed)) * smoothstep(0.0006, 0.0025, px);

	// --- colour: white crystals on grey-blue hoar, glassy grey where soaked
	float bright = clamp(lines * 1.15 + hoar * 0.35, 0.0, 1.0);
	vec3 frost = mix(hoar_tint.rgb, frost_tint.rgb, max(bright, smoothstep(0.5, 1.3, body_thick) * 0.6));
	frost = mix(frost, wet_ice_tint.rgb, soak * 0.60);
	// Glassy ice catches the light along its ridges; dry frost only glints here and there.
	vec2 slope = vec2(dFdx(body), dFdy(body));
	frost += vec3(clamp((slope.x + slope.y) * -9.0, -0.12, 0.30)) * soak * left;
	frost += vec3(step(0.990, frost_hash21(floor(m * 700.0) + seed)) * (1.0 - soak) * lines * 0.5);

	vec3 col = glass_tint.rgb;
	float alpha = 0.09 + 0.04 * open * fresh;  // the glass itself; a shade denser while wet
	frost_over(col, alpha, frost, scatter);
	frost_over(col, alpha, vec3(0.87, 0.90, 0.92), veil * 0.07);
	// A sliding plate: the frost it carried, fused to glassy ice; its broken edge catches the light.
	float plate_body = clamp(carried.z * 0.8 + carried.x * 0.5 + 0.25, 0.0, 1.0);
	float plate_edge = plate * (1.0 - plate) * 4.0;
	vec3 plate_col = mix(wet_ice_tint.rgb * 1.12, frost_tint.rgb, clamp(carried.z * 0.45 + carried.x * 0.25 + plate_edge, 0.0, 1.0));
	frost_over(col, alpha, plate_col, plate * plate_fade * mix(0.30, 0.85, plate_body) + plate_edge * plate_fade * 0.5);
	// Water: a dark rim and a glint for each bead and thread.
	float rim = max(length(big.xy), length(mist.xy));
	frost_over(col, alpha, vec3(0.10, 0.14, 0.17), 0.22 * smoothstep(0.55, 1.0, rim) + 0.10 * water * smoothstep(0.3, 1.0, water_n.x));
	frost_over(col, alpha, vec3(0.95, 0.98, 1.0), clamp(water_glint * water * 0.45 + big.w * 0.6 + mist.w * 0.4, 0.0, 1.0));
	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
