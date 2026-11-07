// Issue #281, MCode/MiniMax: V3's shape and alpha model, organic thaw.
//
// The approved control (lit_frosted_glass_v3_white_tint_only.gdshader) is
// untouched. This variant changes only HOW the thaw front moves and how the
// frost gives way to wet glass:
//
//   * a melt source is a finger, not a disc: every lobe is stretched, turned,
//     lobed and creeps downwards as it grows, the way meltwater runs down a
//     cold pane;
//   * the front is pulled by a two-level domain warp, so lobes arrive as
//     tongues that merge instead of three round patches;
//   * the open area stays solid: the tearing happens at the threshold, where
//     the front actually is, and it deepens as the pane warms;
//   * crystal density is uneven - some patches hold on longer than others;
//   * behind the front the glass is wet first: a band of meltwater follows the
//     retreating edge and thins out deeper inside.
//
// The alpha model, the neutral white tint, the real scene lighting and the cold
// rim are the control's. No new light, no emission, no production material.
shader_type spatial;
render_mode cull_disabled, blend_mix, depth_prepass_alpha;

#include "res://shaders/environment/windows/frost_pattern.gdshaderinc"
#include "res://shaders/common/sdf_smooth_union.gdshaderinc"

uniform vec4 frost_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 glass_tint : source_color = vec4(0.78, 0.78, 0.78, 1.0);
uniform float heated_warmth : hint_range(0.0, 1.0) = 0.0;
uniform float growth_seed = 0.28;
uniform float melt_seed = 0.73;
uniform float pane_aspect = 1.81818;
uniform float merge_width = 0.075;
uniform vec4 blob_data[16];
uniform int blob_count = 0;


// The distance to one melt lobe. Real melt spreads as a finger that runs
// down, so the lobe is stretched downwards, turned a little and lobed, and its
// centre creeps down while it grows.
float lobe_distance(vec4 blob, vec2 p, vec2 metric_scale, float growth) {
	vec2 centre = (blob.xy - vec2(0.5)) * metric_scale;
	float h = frost_hash21(blob.xy * 13.7 + vec2(melt_seed, growth_seed));
	float h2 = frost_hash21(blob.xy * 5.1 + vec2(growth_seed, melt_seed));
	// Mostly downwards, with a spread, so the fingers do not all fall alike.
	float angle = 1.5708 + (h - 0.5) * 1.15;
	vec2 axis = vec2(cos(angle), sin(angle));
	// The melt centre creeps down as the lobe grows.
	centre.y += growth * mix(0.05, 0.16, h2);
	vec2 delta = p - centre;
	float across = dot(delta, axis);
	float along = dot(delta, vec2(-axis.y, axis.x));
	// Fingers are longer along their own axis than across it.
	along *= mix(0.58, 0.92, h2);
	float radius = blob.z * mix(0.70, 1.08, h);
	// A lobed outline, so no lobe is ever a circle.
	float ang = atan(along, across);
	float lobe = 1.0 + 0.20 * sin(ang * 3.0 + h * 6.28318) + 0.10 * sin(ang * 5.0 - h * 3.1);
	return length(vec2(across, along)) - radius * lobe;
}


void fragment() {
	// Reuse the existing crystalline frost, its cold-edge distribution and glints.
	// With thaw=0 these values match the baseline before heating.
	vec3 f = frost_pattern(UV, frost_pane_m(UV, VERTEX), COLOR.r, 0.0, COLOR.b + growth_seed, melt_seed + COLOR.b);

	// Two-level domain warp. The broad flow bends the whole thaw field, the
	// finer one frays it where the front actually is, and both break the radial
	// symmetry at the source.
	vec2 macro_a = UV * vec2(3.6, 2.9) + vec2(melt_seed * 1.4, growth_seed * 1.1);
	vec2 macro_b = UV * vec2(4.7, 4.1) + vec2(8.3 + growth_seed, 4.7 + melt_seed);
	vec2 flow = vec2(frost_fbm(macro_a) - 0.485, frost_fbm(macro_b) - 0.485);
	vec2 fine_a = UV * vec2(9.1, 7.4) + flow * 3.2 + vec2(2.7, 6.1);
	vec2 fine_b = UV * vec2(11.3, 8.6) + flow * 3.2 + vec2(5.9, 1.3);
	flow += vec2(frost_fbm(fine_a) - 0.485, frost_fbm(fine_b) - 0.485) * 0.55;

	vec2 metric_scale = vec2(pane_aspect, 1.0);
	vec2 p = (UV - vec2(0.5)) * metric_scale + flow * vec2(0.21, 0.16);
	float growth = clamp(heated_warmth, 0.0, 1.0);
	float d = 100.0;
	for (int i = 0; i < 16; i++) {
		if (i >= blob_count) {
			break;
		}
		float sd = lobe_distance(blob_data[i], p, metric_scale, growth);
		d = i == 0 ? sd : smooth_union(d, sd, merge_width);
	}

	// The SAME cold rim / crystal pattern still own what is frosted.
	// The field itself stays quiet enough to keep the open area solid; the
	// tearing happens at the threshold, and it deepens as the pane warms.
	vec2 m = UV * vec2(pane_aspect, 1.0);
	float broad = frost_fbm(UV * vec2(7.4, 5.2) + vec2(melt_seed * 4.8)) - 0.485;
	float middle = frost_fbm(UV * vec2(23.0, 15.0) + vec2(10.8, melt_seed * 12.2)) - 0.485;
	float fine = frost_value_noise(UV * vec2(78.0, 56.0) + vec2(melt_seed * 19.1)) - 0.5;
	float cold_bias = 0.065 * (0.62 - frost_cold_rank(m, metric_scale));
	float field = d + broad * 0.16 + middle * 0.075 + fine * 0.014 + cold_bias;
	float tear = (broad * 0.90 + middle * 0.48 + fine * 0.16) * mix(0.30, 1.0, growth);

	// Keep the open area solid; only the threshold (the thaw front) is torn.
	float cleared = 1.0 - smoothstep(-0.012 + tear * 0.050, 0.030 + tear * 0.050, field);
	cleared *= smoothstep(0.0, 0.16, heated_warmth);
	float edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	cleared *= smoothstep(0.012, 0.125, edge);

	// Stage 1: a broad precursor follows the SAME coherent thaw field.
	// Its outer fringe first loses crystal density, rather than disappearing
	// behind a sudden solid circular alpha mask. There is no independent
	// animated noise/time source; the stage is driven only by heated_warmth.
	float pre_thaw = 1.0 - smoothstep(0.055, 0.185, field);
	pre_thaw *= smoothstep(0.05, 0.23, heated_warmth);
	float film_thinning = (1.0 - cleared) * pre_thaw;
	float crystal_weight = clamp(f.x * 0.7 + f.y * 0.3, 0.0, 1.0);
	float preferential_melt = mix(0.72, 0.37, crystal_weight);
	float frost_survival = (1.0 - cleared) * (1.0 - film_thinning * preferential_melt);

	// Crystal density is not even: patches of the rim hold on longer than
	// the rest, so the frost thins unevenly instead of fading as one sheet.
	float density = frost_fbm(UV * vec2(5.6, 4.1) + vec2(3.1, melt_seed * 5.0));
	frost_survival *= mix(mix(0.70, 1.0, smoothstep(0.30, 0.78, density)), 1.0, 1.0 - smoothstep(0.03, 0.28, heated_warmth));

	// Stage 2: dense fern tips outlast the translucent base, but only on the
	// advancing boundary. Their persistence is spatial, not a static white ring.
	float front = 1.0 - smoothstep(0.008, 0.086, abs(field));
	float crystal_resistance = clamp(0.12 + f.y * 0.19 + f.x * 0.20, 0.0, 0.5);
	float tip_survival = cleared * front * crystal_resistance;
	f.x *= frost_survival + tip_survival;
	f.y *= frost_survival + tip_survival * 0.82;

	// Stage 3: a thin translucent film forms behind the receding frost.
	// It is densest just behind the moving front and fades deeper inside, so
	// the glass reads as wet where the frost let go, not as wet everywhere.
	float newly_wet = 1.0 - smoothstep(-0.015, 0.12, abs(field));
	float behind_front = smoothstep(-0.17, -0.02, field) * (1.0 - smoothstep(-0.02, 0.07, field));
	float wet_interior = cleared * (0.28 + 0.26 * frost_fbm(UV * vec2(14.0, 8.0) + melt_seed * 5.0));
	float dampness = smoothstep(0.12, 0.31, heated_warmth);
	float wet_film = clamp((newly_wet * 0.55 + wet_interior * 0.30 + behind_front * cleared * 0.46) * dampness, 0.0, 1.0);

	// Sparse uneven drainage, *not* six evenly spaced bright white lines.
	// Stable seed picks only a few tracks. Each has different start / delay,
	// bends on a broad noise field and has a subtle, short translucent tail.
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
		// The track leans the way the melt leans.
		bending += flow.x * 0.040 * (1.0 - lane * 0.11);
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

	// Stage 4: frozen frost, translucent precursor, water and clear glass
	// retain distinct optical densities. Water catches a limited neutral-white
	// highlight without taking over the intentionally NPR crystal language.
	vec3 glass_base = frost_color(UV, f, glass_tint.rgb, frost_tint.rgb);
	glass_base = mix(glass_base, glass_tint.rgb * 0.78, wet_film * 0.22);
	vec3 wet_highlight = vec3(0.96, 0.96, 0.96);
	ALBEDO = mix(glass_base, wet_highlight, clamp(wet_trace * 0.19 + front * wet_film * 0.09, 0.0, 0.42));
	float frost_alpha = clamp(f.x * 0.95 + f.y * 0.15, 0.0, 1.0);
	float liquid_alpha = wet_film * 0.19 + wet_trace * 0.13;
	ALPHA = clamp(mix(0.095, 0.995, frost_alpha) + liquid_alpha, 0.0, 1.0);
	ROUGHNESS = mix(mix(0.25, 0.96, f.x), 0.085, wet_film);
	// Lit-material test: real scene sun and stove SpotLight3D shade the
	// water differently from frosted crystal; no fake highlights or lights.
	METALLIC = 0.0;
	SPECULAR = mix(0.48, 0.95, clamp(wet_film + wet_trace * 0.5, 0.0, 1.0));
}
