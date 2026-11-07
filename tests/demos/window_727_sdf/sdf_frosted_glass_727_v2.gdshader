// R&D #281: same existing frost renderer, with the thaw front replaced by the
// reusable blob SDF union. Test-only material, never assigned to the production GLB.
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

	// Melting is gradual: crystal tips on the *boundary* resist longer than
	// the surrounding thin film, leaving small white fronds in the transition.
	// This affects only a narrow band, not the shape's connected interior.
	float fringe = 1.0 - smoothstep(0.01, 0.075, abs(field));
	float crystal_resistance = clamp(0.15 + 0.38 * f.x + 0.12 * f.y, 0.0, 0.65);
	float residual = cleared * fringe * crystal_resistance;
	float wet_band = fringe * cleared * heated_warmth * 0.55;
	f.x *= 1.0 - cleared + residual;
	f.y *= 1.0 - cleared + residual * 0.45;
	f.z = max(f.z, wet_band * 0.48);

	ALBEDO = mix(frost_color(UV, f, glass_tint.rgb, frost_tint.rgb), glass_tint.rgb * 0.8, f.z * 0.5);
	ALPHA = mix(0.095, 0.995, clamp(f.x * 0.95 + f.y * 0.15, 0.0, 1.0)) + f.z * 0.12;
	ROUGHNESS = mix(mix(0.18, 0.96, f.x), 0.05, f.z);
}
