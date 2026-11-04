// R&D #281 V3: staged crystalline thinning, damp glass and slow melt trails
// on the same reusable blob SDF union. Test-only; no production changes. Test-only material, never assigned to the production GLB.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_prepass_alpha;

#include "res://shaders/environment/windows/frost_pattern.gdshaderinc"
#include "res://shaders/common/sdf_smooth_union.gdshaderinc"

uniform vec4 frost_tint : source_color = vec4(0.88, 0.94, 0.98, 1.0);
uniform vec4 glass_tint : source_color = vec4(0.62, 0.76, 0.86, 1.0);
uniform float heated_warmth : hint_range(0.0, 1.0) = 0.0;
uniform float growth_seed = 0.28;
uniform float melt_seed = 0.73;
uniform float pane_aspect = 1.81818;
uniform float merge_width = 0.075;
uniform vec4 blob_data[16];
uniform int blob_count = 0;

void fragment() {
	// Reuse the existing crystalline frost, its cold-edge distribution and glints.
	// With thaw=0 these values match the baseline before heating.
	vec3 f = frost_pattern(UV, frost_pane_m(UV, VERTEX), COLOR.r, 0.0, COLOR.b + growth_seed, melt_seed + COLOR.b);

	// Domain distortion gently bends the SDF *before* union. All lobes still
	// coalesce through the original smooth_union, not through animated textures.
	// The two independent fields break radial symmetry at the source.
	vec2 macro_a = UV * vec2(4.3, 3.4) + vec2(melt_seed * 1.4, growth_seed * 1.1);
	vec2 macro_b = UV * vec2(5.2, 4.7) + vec2(8.3 + growth_seed, 4.7 + melt_seed);
	vec2 flow = vec2(
		frost_fbm(macro_a) - 0.485,
		frost_fbm(macro_b) - 0.485
	);
	vec2 metric_scale = vec2(pane_aspect, 1.0);
	vec2 p = (UV - vec2(0.5)) * metric_scale + flow * vec2(0.19, 0.15);
	float d = 100.0;
	for (int i = 0; i < 16; i++) {
		if (i >= blob_count) {
			break;
		}
		vec4 blob = blob_data[i];
		vec2 centre = (blob.xy - vec2(0.5)) * metric_scale;
		float sd = length(p - centre) - max(blob.z, 0.00001);
		d = i == 0 ? sd : smooth_union(d, sd, merge_width);
	}

	// The SAME cold rim / crystal pattern still own what is frosted.
	// Shape the moving boundary at three spatial scales, not by adding
	// high-frequency noise everywhere on the pane. The medium bands make
	// irregular inlets and the fine band frays their edge like wet ice.
	vec2 m = UV * vec2(pane_aspect, 1.0);
	float broad = frost_fbm(UV * vec2(8.6, 5.9) + vec2(melt_seed * 4.8)) - 0.485;
	float middle = frost_fbm(UV * vec2(27.0, 16.0) + vec2(10.8, melt_seed * 12.2)) - 0.485;
	float fine = frost_value_noise(UV * vec2(92.0, 63.0) + vec2(melt_seed * 19.1)) - 0.5;
	float cold_bias = 0.065 * (0.62 - frost_cold_rank(m, metric_scale));
	float field = d + broad * 0.23 + middle * 0.105 + fine * 0.020 + cold_bias;

	// Keep the open area solid; only the threshold (the thaw front) is torn.
	float cleared = 1.0 - smoothstep(-0.010, 0.028, field);
	cleared *= smoothstep(0.0, 0.16, heated_warmth);
	float edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	cleared *= smoothstep(0.012, 0.125, edge);

	// Stage 1: a broad precursor follows the SAME coherent SDF union.
	// Its outer fringe first loses crystal density, rather than disappearing
	// behind a sudden solid circular alpha mask. There is no independent
	// animated noise/time source; the stage is driven only by heated_warmth.
	float pre_thaw = 1.0 - smoothstep(0.055, 0.185, field);
	pre_thaw *= smoothstep(0.05, 0.23, heated_warmth);
	float film_thinning = (1.0 - cleared) * pre_thaw;
	float crystal_weight = clamp(f.x * 0.7 + f.y * 0.3, 0.0, 1.0);
	float preferential_melt = mix(0.72, 0.37, crystal_weight);
	float frost_survival = (1.0 - cleared) * (1.0 - film_thinning * preferential_melt);
	
	// Stage 2: dense fern tips outlast the translucent base, but only on the
	// advancing boundary. Their persistence is spatial, not a static white ring.
	float front = 1.0 - smoothstep(0.008, 0.086, abs(field));
	float crystal_resistance = clamp(0.12 + f.y * 0.19 + f.x * 0.20, 0.0, 0.5);
	float tip_survival = cleared * front * crystal_resistance;
	f.x *= frost_survival + tip_survival;
	f.y *= frost_survival + tip_survival * 0.82;

	// Stage 3: a thin translucent film forms behind the receding frost.
	// It is slightly denser near the moving front and becomes faint over time.
	float newly_wet = 1.0 - smoothstep(-0.015, 0.12, abs(field));
	float wet_interior = cleared * (0.35 + 0.30 * frost_fbm(UV * vec2(14.0, 8.0) + melt_seed * 5.0));
	float dampness = smoothstep(0.12, 0.31, heated_warmth);
	float wet_film = clamp((newly_wet * 0.62 + wet_interior * 0.35) * dampness, 0.0, 1.0);

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
	// retain distinct optical densities. Water catches a limited blue-white
	// highlight without taking over the intentionally NPR crystal language.
	vec3 glass_base = frost_color(UV, f, glass_tint.rgb, frost_tint.rgb);
	glass_base = mix(glass_base, glass_tint.rgb * 0.78, wet_film * 0.22);
	vec3 wet_highlight = vec3(0.82, 0.93, 0.96);
	ALBEDO = mix(glass_base, wet_highlight, clamp(wet_trace * 0.19 + front * wet_film * 0.09, 0.0, 0.42));
	float frost_alpha = clamp(f.x * 0.95 + f.y * 0.15, 0.0, 1.0);
	float liquid_alpha = wet_film * 0.19 + wet_trace * 0.13;
	ALPHA = clamp(mix(0.095, 0.995, frost_alpha) + liquid_alpha, 0.0, 1.0);
	ROUGHNESS = mix(mix(0.18, 0.96, f.x), 0.07, wet_film);
}
