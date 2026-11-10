// R&D #281, natural thaw: frost as a scattering layer over the real view (blurred by thickness), a thaw that
// wets, breaks up and clears by local thickness and warmth, rivulets that cut tracks, beads on cleared glass.
// Test-only material for the FrontWindow1 probe; the production glass and frost_pattern include are untouched.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

#include "res://shaders/environment/windows/frost_pattern.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform vec3 thick_frost : source_color = vec3(0.955, 0.962, 0.958);
uniform vec3 thin_frost : source_color = vec3(0.70, 0.80, 0.89);
uniform vec3 wet_frost : source_color = vec3(0.52, 0.62, 0.68);
uniform vec3 rim_grime : source_color = vec3(0.90, 0.89, 0.84);
uniform vec3 glass_tint : source_color = vec3(0.93, 0.965, 0.97);
uniform float heated_warmth : hint_range(0.0, 1.0) = 0.0;
uniform float growth_seed = 0.28;
uniform float melt_seed = 0.73;
uniform float pane_aspect = 1.81818;
// Same interface as the SDF probe: xy = a warm spot on the pane (UV), the rest is unused here.
uniform vec4 blob_data[16];
uniform int blob_count = 0;

const int LANES = 14;

// Warmth a texel needs before it starts to thaw, without the crystal detail (used for drip starts too):
// far from the warm spots, near the frame and low on the pane all hold out longer.
float thaw_need_base(vec2 uv, vec2 pane) {
	vec2 m = uv * pane;
	float away = 0.9;
	for (int i = 0; i < 16; i++) {
		if (i >= blob_count) {
			break;
		}
		away = min(away, length((uv - blob_data[i].xy) * vec2(pane_aspect, 1.0)));
	}
	if (blob_count == 0) {
		away = length((uv - vec2(0.5, 0.42)) * vec2(pane_aspect, 1.0));
	}
	float rank = clamp(frost_cold_rank(m, pane), 0.0, 1.0);
	float lobes = frost_fbm(m * 1.7 + vec2(melt_seed * 7.1, melt_seed * 3.3)) - 0.485;
	float tongues = frost_fbm(m * 7.0 + vec2(4.1, melt_seed * 9.7)) - 0.485;
	// The frame itself stays below freezing: the last few centimetres hold out to the end.
	float frame = 1.0 - smoothstep(0.0, 0.30, rank);
	// Warm air rises along the glass: the upper pane leads, the sill lags.
	return 0.12 + 0.30 * clamp(away / 0.95, 0.0, 1.0) + 0.20 * (1.0 - rank) * (1.0 - rank)
		+ 0.40 * frame * mix(0.5, 1.0, uv.y) + 0.44 * uv.y * uv.y + lobes * 0.66 + tongues * 0.24;
}

// One layer of water beads scattered over a `cell_m` grid: xy = lens normal, z = bead mask, w = highlight.
vec4 beads(vec2 m, float cell_m, float seed, float grow, float density) {
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
			float r = mix(0.07, 0.30, pow(frost_hash21(id + 9.1 + seed), 2.0)) * grow;
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

void fragment() {
	vec2 pane = frost_pane_m(UV, VERTEX);
	vec2 m = UV * pane;
	float coverage = smoothstep(0.0, 0.25, COLOR.r);
	float t = heated_warmth * 0.94;

	// --- the frost: fern veins on a bent grain over a granular hoar base, thicker at the cold frame
	vec2 bend = vec2(frost_fbm(m * 1.9 + growth_seed * 3.0), frost_fbm(m * 1.9 + vec2(5.2, 1.3) + growth_seed * 3.0)) - 0.485;
	vec2 uv_c = clamp(UV + bend * vec2(0.035, 0.06), vec2(0.0), vec2(1.0));
	vec3 f = frost_pattern(uv_c, pane, max(COLOR.r, 0.86), 0.0, COLOR.b + growth_seed, melt_seed + COLOR.b);
	float rank = clamp(frost_cold_rank(m, pane), 0.0, 1.0);
	float e = 0.01;
	vec2 grad = vec2(frost_cold_rank(m + vec2(e, 0.0), pane) - frost_cold_rank(m - vec2(e, 0.0), pane),
		frost_cold_rank(m + vec2(0.0, e), pane) - frost_cold_rank(m - vec2(0.0, e), pane));
	vec2 g = length(grad) > 1e-4 ? normalize(grad) : vec2(0.0, -1.0);
	// Needles lie along the growth direction: long that way, fine across it.
	vec2 along = vec2(dot(m, g), dot(m, vec2(-g.y, g.x)));
	float needles = frost_value_noise(vec2(along.x * 16.0, along.y * 150.0) + growth_seed * 19.0);
	float cloud = frost_fbm(m * 3.4 + growth_seed * 11.0);
	float grain = frost_fbm(m * 46.0 + 3.7);
	float hoar = mix(0.34, 0.98, (1.0 - rank) * (1.0 - rank)) * (0.50 + 1.0 * cloud);
	hoar += smoothstep(0.80, 1.0, UV.y) * 0.34;  // drifted up from the sill
	float smooth_thick = coverage * (hoar + f.x * 0.62);
	float thick = smooth_thick + coverage * hoar * (0.20 * (grain - 0.5) + 0.16 * (needles - 0.5));

	// --- when this texel thaws: thin glass between the veins goes first, thick fern and rim last
	float need = thaw_need_base(UV, pane) + (smooth_thick - 0.75) * 0.17 + f.x * 0.05
		+ (frost_value_noise(m * 38.0 + melt_seed * 5.0) - 0.5) * 0.04;
	float s = (t - need) / 0.24;  // <0 dry, 0..0.6 soaking, 0.6..1 breaking up, >1 clear

	// --- rivulets: a bead gathers at the thaw front, runs down a wandering lane and cuts a wet track
	float track = 0.0;      // frost cleared along the lane
	float track_wet = 0.0;  // frost soaked beside it
	float water = 0.0;      // water body: thread and head
	vec2 water_n = vec2(0.0);
	float water_glint = 0.0;
	float arrived = 0.0;
	for (int k = 0; k < LANES; k++) {
		float lane = float(k);
		float h = frost_hash21(vec2(lane * 3.71 + melt_seed * 9.0, 6.13));
		float x0 = (lane + 0.18 + 0.64 * frost_hash21(vec2(lane, 2.9 + melt_seed))) / float(LANES);
		float y0 = mix(0.22, 0.74, frost_hash21(vec2(lane, 7.91 + melt_seed)));
		float start_need = thaw_need_base(vec2(x0, y0), pane);
		// It lets go while its patch is still soaking, so it runs into the frost below.
		float phase = clamp((t - start_need - 0.07) * mix(1.7, 3.0, h), 0.0, 1.4);
		if (phase <= 0.0) {
			continue;
		}
		// It creeps, then lets go: slow at first, faster as it gathers what it meets.
		float head = y0 + (1.02 - y0) * phase * phase * 0.75;
		arrived += smoothstep(0.985, 1.0, head);
		float wander = (frost_value_noise(vec2(m.y * 9.0 + lane * 3.3, h * 9.2)) - 0.5) * 0.030
			+ (frost_value_noise(vec2(m.y * 37.0 + lane * 1.7, 4.4)) - 0.5) * 0.006;
		float dx = m.x - (x0 * pane.x + wander);
		float half_w = mix(0.0045, 0.0085, h);
		float in_len = smoothstep(y0 - 0.004, y0 + 0.012, UV.y) * (1.0 - smoothstep(head - 0.004, head + 0.003, UV.y));
		float body = 1.0 - smoothstep(half_w, half_w + 0.0022, abs(dx));
		track = max(track, body * in_len);
		track_wet = max(track_wet, (1.0 - smoothstep(half_w, half_w * 4.5, abs(dx))) * in_len);
		// The thread of water thins behind the head and breaks into a string of beads.
		float behind = (head - UV.y) * pane.y;
		float broken = mix(1.0, smoothstep(0.42, 0.62, frost_value_noise(vec2(m.y * 150.0 + lane * 9.0, h * 3.0))),
			smoothstep(0.03, 0.14, behind));
		float thread_w = half_w * mix(0.50, 0.22, smoothstep(0.0, 0.25, behind));
		float thread = (1.0 - smoothstep(thread_w * 0.6, thread_w, abs(dx))) * in_len * broken;
		vec2 tip = vec2(dx, (UV.y - head) * pane.y + 0.004);
		tip.y *= tip.y < 0.0 ? 0.55 : 1.0;  // teardrop: long above, round below
		float head_r = half_w * 0.95;
		float bead = (1.0 - smoothstep(0.75, 1.0, length(tip) / head_r)) * step(head, 1.0);
		float here = max(thread, bead);
		if (here > water) {
			water = here;
			water_n = bead > thread ? tip / head_r : vec2(dx / max(thread_w, 1e-4), 0.0);
			water_glint = 1.0 - smoothstep(0.0, 0.4, length(water_n - vec2(-0.36, bead > thread ? -0.40 : 0.0)));
		}
	}

	// --- what is left of the frost
	float soak = max(smoothstep(-0.15, 0.6, s), track_wet * 0.85);
	// It does not fade: it breaks into slush islands that shrink.
	float islands = frost_fbm(m * 17.0 + melt_seed * 23.0) * 0.7 + frost_value_noise(m * 55.0 + 8.3) * 0.3;
	float left = 1.0 - smoothstep(0.0, 1.0, (s - 0.6) * 2.5 - (islands - 0.5) * 1.5);
	left *= 1.0 - track * 0.95;
	float body_thick = thick * left * mix(1.0, 0.55, soak);
	float scatter = 1.0 - exp(-body_thick * mix(3.3, 0.95, soak));  // soaked ice lets the view through

	// --- water on the glass that has cleared
	float open = clamp(1.0 - left, 0.0, 1.0) * smoothstep(0.02, 0.2, t);
	float fresh = 1.0 - smoothstep(1.0, 4.2, s);  // beads thin out as the pane dries
	vec4 big = beads(m, 0.042, melt_seed, open * mix(0.5, 1.0, fresh), 0.46 * mix(0.4, 1.0, fresh));
	vec4 mist = beads(m + 0.37, 0.013, melt_seed + 0.4, open * fresh, 0.60 * fresh);
	// Meltwater stands along the sill once it has run down.
	float sill_h = (0.004 + 0.011 * clamp(arrived / 6.0, 0.0, 1.0)) * (0.7 + 0.6 * frost_value_noise(vec2(m.x * 23.0, 1.7)));
	float sill = (1.0 - smoothstep(sill_h * 0.75, sill_h, (1.0 - UV.y) * pane.y)) * smoothstep(0.0, 1.5, arrived);

	// --- the view through: blurred by what frost is left, bent by water
	vec2 lens = water_n * water * 0.011 + big.xy * 0.010 + mist.xy * 0.004;
	vec2 jitter = (vec2(grain, needles) - 0.5) * 0.006 * scatter;
	float blur = 5.6 * clamp(body_thick * 1.7, 0.0, 1.0) * (1.0 - max(water, big.z));
	vec3 view = textureLod(screen_tex, SCREEN_UV - lens + jitter, blur).rgb * glass_tint;
	// A soaked pane and a water film read a shade darker than dry clear glass.
	view *= 1.0 - 0.07 * open * fresh - 0.10 * sill;

	// --- the frost itself: white where thick, blue where thin, grey-green where soaked, grimy at the frame
	vec3 frost = mix(thin_frost, thick_frost, smoothstep(0.25, 1.05, body_thick));
	frost = mix(frost, rim_grime, (1.0 - rank) * (1.0 - rank) * 0.30 * (0.5 + cloud));
	frost = mix(frost, wet_frost, soak * 0.62);
	// Relief: the crystal layer catches the daylight on one side of each ridge.
	float relief_h = smooth_thick * left;
	vec2 slope = vec2(dFdx(relief_h), dFdy(relief_h));
	float relief = clamp(1.0 + (slope.x + slope.y) * -1.0, 0.95, 1.05);
	relief *= 0.95 + 0.10 * needles;  // the needle grain as tone, not as emboss
	frost *= mix(1.0, relief, 1.0 - soak * 0.6);
	float sparkle = step(0.988, frost_hash21(floor(m * 520.0) + growth_seed)) * (1.0 - soak) * smoothstep(0.5, 1.0, body_thick);
	frost += vec3(1.0) * (f.y * 0.35 + sparkle * 0.55);
	// Soaked ice turns glassy: a faint sheen along its melting edge.
	float edge_sheen = soak * (1.0 - soak) * 4.0 * left;
	frost += vec3(0.10, 0.12, 0.13) * edge_sheen;

	vec3 col = mix(view, frost, scatter);
	// Water: dark rim, bright glint.
	float rim_q = max(length(big.xy), length(mist.xy));
	col *= 1.0 - 0.26 * smoothstep(0.55, 1.0, rim_q);
	// A running thread only shades its far edge; the track it cut stays clear.
	col *= 1.0 - 0.14 * water * smoothstep(0.3, 1.0, water_n.x);
	col += vec3(0.95, 0.98, 1.0) * (water_glint * water * 0.38 + big.w * 0.60 + mist.w * 0.35 + sill * 0.08);
	ALBEDO = col;
	ALPHA = 1.0;
}
