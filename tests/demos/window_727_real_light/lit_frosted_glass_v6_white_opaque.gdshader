// Issue #281, V6 fully white, OPAQUE UNTHAWED frost.
// Preserve source V3 crystalline geometry and smooth-union melting.
// Frost optical coverage follows the melt FIELD, never sparse crystal detail.
// Test-only: no production material changes.
shader_type spatial;
render_mode cull_disabled, blend_mix, depth_prepass_alpha;

#include "res://shaders/environment/windows/frost_pattern.gdshaderinc"
#include "res://shaders/common/sdf_smooth_union.gdshaderinc"

uniform vec4 frost_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 glass_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
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
	// A permanently frozen perimeter: never let the clear mask reach
	// the frame before the thaw front actually crosses it.
	cleared *= smoothstep(0.075, 0.135, edge);

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

	// Stage 4: optically frosted parts are SOLID WHITE, not a transparent
	// overlay whose opacity depends on sparse fern/detail masks. Those masks
	// remain ONLY for subtle crystal relief and lighting microstructure.
	// The SDF thaw field is the sole driver of actual glass transparency.
	float ice_coverage = 1.0 - cleared;
	float fine_grain = (frost_fbm(UV * vec2(19.0, 13.0) + growth_seed) - 0.5) * 0.055;
	float white_relief = clamp(0.958 + 0.032 * f.x + fine_grain, 0.91, 1.0);
	vec3 ice_white = vec3(1.0) * white_relief;
	vec3 neutral_glass = vec3(0.97);
	vec3 wet_highlight = vec3(1.0);
	neutral_glass = mix(neutral_glass, wet_highlight, wet_trace * 0.08);
	ALBEDO = mix(neutral_glass, ice_white, ice_coverage);

	// Frost to the very edge is opaque even between thin crystal branches.
	// Only genuinely thawed areas let the outside show through. A narrow
	// front blends to a clear wet pane, with no blue-transparent frost rim.
	float clear_alpha = clamp(0.025 + wet_film * 0.075 + wet_trace * 0.055, 0.025, 0.16);
	ALPHA = mix(clear_alpha, 1.0, ice_coverage);

	// Diffuse forward scattering from the bright frozen daylight keeps the
	// densely frosted layer white under the game's very dim, cool sun.
	// Low and local, not a full unshaded material: wet and crystalline facets
	// still have the game's real lighting/specular response.
	EMISSION = vec3(0.16) * ice_coverage * (0.78 + 0.22 * f.x);
	// Break the identical mirrored plate response into real microfacets.
	// Rough chalky frost, smoother crystalline branches and glossy, thin water
	// respond to the actual sun/room stove — not to fake emissive highlights.
	float crystal_branch = clamp(f.y * 0.92 + f.x * 0.18, 0.0, 1.0);
	float frost_roughness = mix(0.69, 0.25, crystal_branch);
	ROUGHNESS = mix(frost_roughness, 0.045, clamp(wet_film * 0.9 + wet_trace * 0.25, 0.0, 1.0));
	METALLIC = 0.0;
	SPECULAR = mix(0.46 + crystal_branch * 0.04, 0.50, clamp(wet_film + wet_trace * 0.4, 0.0, 1.0));

	// Small stable surface-normal irregularities allow individual crystalline
	// ridges to catch real light; wet patches stay optically smoother.
	vec2 facets = vec2(
		frost_value_noise(UV * vec2(80.0, 57.0) + vec2(1.0, 3.2)),
		frost_value_noise(UV * vec2(79.0, 59.0) + vec2(7.7, 0.9))
	) - vec2(0.5);
	float micro_bump = clamp(f.x * 0.24 + crystal_branch * 0.42, 0.0, 0.50) * (1.0 - wet_film);
	NORMAL = normalize(NORMAL + vec3(facets * micro_bump, 0.0));
}
