shader_type spatial;
render_mode cull_disabled, blend_mix, depth_prepass_alpha;

// Issue #281, new art iteration (MCode). Test-only: no production material is
// changed. The production frost pattern and the approved white tint are kept;
// only the thaw geometry and the rim composition are new.
//
// The old thaw was three growing discs, so the pane read as spots. Here the melt
// travels as elongated, bent, branching tongues out of an irregular warm patch,
// so the cleared area grows by length and by branching, never as a circle.
//
// Composition follows real window frost (Caltech "Guide to Frost"):
//   - separate frond clusters with calm glass between them (production pattern);
//   - the frame stays denser, but the cold rim is broken by a perimeter noise
//     instead of a uniform white band;
//   - the moving front is torn at three spatial scales, so its edge is never a
//     smooth SDF contour;
//   - on the front: dense frost -> thin crystals -> wet film -> clear glass.

#include "res://shaders/environment/windows/frost_pattern.gdshaderinc"
#include "res://shaders/common/sdf_smooth_union.gdshaderinc"

uniform vec4 frost_tint : source_color = vec4(0.96, 0.96, 0.96, 1.0);
uniform vec4 glass_tint : source_color = vec4(0.58, 0.58, 0.58, 1.0);
uniform float heated_warmth : hint_range(0.0, 1.0) = 0.0;
uniform float growth_seed = 0.28;
uniform float melt_seed = 0.73;
uniform float pane_aspect = 1.81818;
uniform float merge_width = 0.045;

const int TONGUE_COUNT = 13;

// Distance to a segment with a radius: a capsule. The tongue is a line that
// grows at its far end, so its shape never becomes a disc.
float sd_segment(vec2 p, vec2 a, vec2 b, float r) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(0.0000001, dot(ba, ba)), 0.0, 1.0);
	return length(pa - ba * h) - r;
}

void fragment() {
	vec2 pane_m = frost_pane_m(UV, VERTEX);
	vec2 m = UV * pane_m;

	// --- the frost itself: the production pattern, untouched --------------
	// The authored coverage of the pane. It leaves clear glass between the
	// crystal clusters, which is what makes the pattern read as frost and not
	// as a milky sheet.
	float coverage = COLOR.r;
	vec3 f = frost_pattern(UV, pane_m, coverage, 0.0, COLOR.b + growth_seed, melt_seed + COLOR.b);

	// The very edge of the pane keeps a hard bright line; fade it out.
	float uv_edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	f.x *= smoothstep(0.0, 0.016, uv_edge);
	f.y *= smoothstep(0.0, 0.016, uv_edge);

	// Large calm stretches and dense stretches, instead of one even field.
	float density_field = frost_fbm(UV * vec2(2.3, 1.8) + vec2(melt_seed * 8.7, 3.1));
	f.x *= mix(0.42, 1.0, density_field);
	f.y *= mix(0.42, 1.0, density_field);

	// --- broken cold rim: denser at the frame, never a white band ---------
	float rank = frost_cold_rank(m, pane_m);
	float rim = 1.0 - smoothstep(0.16, 0.72, rank);
	vec2 rel = UV - vec2(0.5);
	float rim_angle = atan(rel.y, rel.x);
	float rim_noise = 0.22 + 0.78 * frost_fbm(vec2(cos(rim_angle), sin(rim_angle)) * 1.7 + vec2(melt_seed * 6.1, 2.3));
	rim_noise *= 0.55 + 0.45 * frost_fbm(UV * vec2(5.0, 4.0) + vec2(melt_seed * 3.1));
	f.x *= mix(1.0, rim_noise, rim * 0.85);
	f.y *= mix(1.0, rim_noise, rim * 0.85);

	// --- the thaw field ----------------------------------------------------
	// The pane metric used here is normalised: x spans +-0.909, y spans +-0.5.
	vec2 pc = vec2((UV.x - 0.5) * pane_aspect, UV.y - 0.5) - vec2(0.0, 0.02);

	// The melt does not start from one warm spot: each clearing has its own
	// nucleus and grows outwards, and they merge later. So the first state of
	// the thaw is a set of separate openings, not one hole.
	float d = 100.0;

	// A broad flow bends the whole field, so the tongues meander.
	vec2 flow = vec2(
		frost_fbm(UV * vec2(3.1, 2.6) + vec2(melt_seed * 3.3)) - 0.485,
		frost_fbm(UV * vec2(4.3, 3.7) + vec2(5.1, melt_seed * 7.7)) - 0.485
	);
	vec2 p = vec2((UV.x - 0.5) * pane_aspect, UV.y - 0.5) + flow * vec2(0.16, 0.13);

	for (int i = 0; i < TONGUE_COUNT; i++) {
		float fi = float(i);
		float h1 = frost_hash21(vec2(fi * 3.17, melt_seed * 7.3 + 0.11));
		float h2 = frost_hash21(vec2(fi * 5.41, melt_seed * 3.9 + 1.7));
		float origin_angle = 6.28318 * h1;
		float origin_radius = 0.06 + 0.40 * fract(h2 * 3.7);
		float delay = 0.24 * fract(h1 * 5.3);
		float g = clamp((heated_warmth - delay) / max(0.001, 1.0 - delay), 0.0, 1.0);
		if (g <= 0.0) {
			continue;
		}
		vec2 o = vec2(cos(origin_angle) * origin_radius, sin(origin_angle) * origin_radius * 0.75) + vec2(0.0, 0.02);
		// Every clearing grows away from the warm middle of the pane.
		vec2 outward = vec2(o.x, o.y - 0.02) / max(0.0001, length(vec2(o.x, o.y - 0.02)));
		float ang = atan(outward.y, outward.x) + (fract(h2 * 23.3) - 0.5) * 0.70;
		vec2 dir = vec2(cos(ang), sin(ang));
		vec2 perp = vec2(-dir.y, dir.x);
		float len = (0.90 + 0.75 * fract(h2 * 7.1)) * pow(g, 0.90);
		float rad = mix(0.020 + 0.015 * fract(h1 * 11.3), 0.085 + 0.055 * fract(h2 * 13.7), pow(g, 0.60));
		float bend = (fract(h1 * 17.9) - 0.5) * 1.10;
		// The axis is two segments, so the tongue bends instead of running straight.
		vec2 mid = o + dir * (len * 0.5) + perp * (len * bend * 0.30);
		vec2 tip = o + dir * len + perp * (len * bend * 0.55);
		d = smooth_union(d, sd_segment(p, o, mid, rad), merge_width);
		d = smooth_union(d, sd_segment(p, mid, tip, rad * 0.86), merge_width);
		// Two side branches appear late and grow sideways.
		float gb = clamp((g - 0.45) / 0.55, 0.0, 1.0);
		if (gb > 0.0) {
			for (int s = 0; s < 2; s++) {
				float sgn = s == 0 ? 1.0 : -1.0;
				float ab = ang + sgn * 0.55 * gb;
				vec2 db = vec2(cos(ab), sin(ab));
				float lb = len * 0.50 * pow(gb, 0.85);
				float rb = rad * (0.40 + 0.30 * gb);
				vec2 base = mid + (tip - mid) * 0.25;
				d = smooth_union(d, sd_segment(p, base, base + db * lb, rb), merge_width * 0.8);
			}
		}
	}

	// --- the front is torn at three scales, never a smooth contour --------
	float broad = frost_fbm(UV * vec2(8.6, 5.9) + vec2(melt_seed * 4.8)) - 0.485;
	float middle = frost_fbm(UV * vec2(27.0, 16.0) + vec2(10.8, melt_seed * 12.2)) - 0.485;
	float fine = frost_value_noise(UV * vec2(92.0, 63.0) + vec2(melt_seed * 19.1)) - 0.5;
	float cold_bias = 0.065 * (0.62 - frost_cold_rank(m, pane_m));
	float field = d + broad * 0.17 + middle * 0.140 + fine * 0.035 + cold_bias;

	// Transparency appears only where the ice actually receded.
	float cleared = 1.0 - smoothstep(-0.004, 0.010, field);
	cleared *= smoothstep(0.0, 0.12, heated_warmth);
	// The frame is the coldest part: the melt never reaches it.
	float edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	cleared *= smoothstep(0.010, 0.085, edge);

	// Stage 1: the frost thins on the front before it disappears.
	float pre_thaw = 1.0 - smoothstep(0.006, 0.090, field);
	pre_thaw *= smoothstep(0.04, 0.20, heated_warmth);
	float crystal_weight = clamp(f.x * 0.7 + f.y * 0.3, 0.0, 1.0);
	float preferential_melt = mix(0.70, 0.35, crystal_weight);
	float frost_survival = (1.0 - cleared) * (1.0 - pre_thaw * preferential_melt);

	// Stage 2: crystal tips outlast the translucent base on the moving front.
	float front = 1.0 - smoothstep(0.008, 0.075, abs(field));
	float crystal_resistance = clamp(0.16 + f.y * 0.28 + f.x * 0.30, 0.0, 0.7);
	float tip_survival = cleared * front * crystal_resistance;
	f.x *= frost_survival + tip_survival;
	f.y *= frost_survival + tip_survival * 0.90;

	// Stage 3: a restrained wet film behind the retreating front.
	float newly_wet = 1.0 - smoothstep(0.0, 0.13, -field);
	float wet_interior = cleared * (0.18 + 0.20 * frost_fbm(UV * vec2(14.0, 8.0) + melt_seed * 5.0));
	float dampness = smoothstep(0.10, 0.30, heated_warmth);
	float wet_film = clamp((newly_wet * 0.55 + wet_interior * 0.30) * dampness, 0.0, 1.0);

	// Stage 4: a few water tracks running down, sparse and uneven.
	float rivulet = 0.0;
	float drop_tip = 0.0;
	for (int k = 0; k < 6; k++) {
		float lane = float(k);
		float h = frost_hash21(vec2(lane * 3.71 + melt_seed * 9.0, 6.13));
		if (h < 0.31) {
			continue;
		}
		float start_y = mix(0.29, 0.49, frost_hash21(vec2(lane, 7.91 + melt_seed)));
		float start_x = (lane + 0.25 + h * 0.48) / 6.0;
		float phase = clamp((heated_warmth - (0.25 + h * 0.31)) * 1.55, 0.0, 1.0);
		float head_y = start_y + phase * (0.16 + 0.26 * h);
		float bending = (frost_value_noise(vec2(UV.y * 7.0 + lane * 3.3, h * 9.2)) - 0.5) * 0.028;
		float wobble = bending + sin(UV.y * 15.0 + h * 11.0) * 0.003;
		float dx = abs(UV.x - start_x - wobble);
		float width = mix(0.0009, 0.0018, h);
		float line = 1.0 - smoothstep(width, width + 0.0016, dx);
		float in_length = smoothstep(start_y - 0.004, start_y + 0.017, UV.y) * (1.0 - smoothstep(head_y - 0.009, head_y + 0.002, UV.y));
		rivulet = max(rivulet, line * in_length * smoothstep(0.08, 0.20, phase));
		vec2 tip_delta = vec2((UV.x - start_x - wobble) * pane_aspect, (UV.y - head_y) * 0.85);
		float rounded_head = 1.0 - smoothstep(0.002, 0.007, length(tip_delta));
		drop_tip = max(drop_tip, rounded_head * smoothstep(0.17, 0.30, phase));
	}
	float wet_trace = max(rivulet * 0.36, drop_tip * 0.52) * cleared * dampness;
	wet_film = max(wet_film, wet_trace * 0.62);
	f.z = max(f.z, wet_film);

	// --- shading: neutral white frost, wet glass stays restrained ---------
	vec3 glass_base = frost_color(UV, f, glass_tint.rgb, frost_tint.rgb);
	glass_base = mix(glass_base, vec3(0.99), smoothstep(0.25, 0.65, f.x) * 0.45);
	// Cheap relief: the edges of the crystal strokes catch the light, so the
	// fronds read as ice instead of flat ink.
	float relief = clamp(length(vec2(dFdx(f.x), dFdy(f.x))) * 22.0, 0.0, 0.45);
	glass_base = mix(glass_base, vec3(1.0), relief);
	glass_base = mix(glass_base, glass_tint.rgb * 0.86, wet_film * 0.15);
	ALBEDO = mix(glass_base, vec3(0.97), clamp(wet_trace * 0.16 + front * wet_film * 0.08, 0.0, 0.35));
	// The thin base between the fronds must stay almost invisible, so the
	// crystals read as separate strokes on the glass instead of a grey haze.
	float frost_alpha = pow(clamp(f.x * 0.95 + f.y * 0.15, 0.0, 1.0), 1.55);
	float liquid_alpha = wet_film * 0.14 + wet_trace * 0.10;
	ALPHA = clamp(mix(0.085, 0.995, frost_alpha) + liquid_alpha, 0.0, 1.0);
	ROUGHNESS = mix(mix(0.22, 0.96, f.x), 0.08, wet_film);
	METALLIC = 0.0;
	SPECULAR = mix(0.42, 0.92, clamp(wet_film + wet_trace * 0.5, 0.0, 1.0));
}
