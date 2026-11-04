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

	vec2 metric_scale = vec2(pane_aspect, 1.0);
	vec2 p = (UV - vec2(0.5)) * metric_scale;
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

	// The blob shape *controls* the thaw; it does not replace the crystal texture.
	// Existing frost noise tears the smooth circles into an irregular melting front.
	float warp = (frost_fbm(UV * vec2(7.5, 5.3) + vec2(melt_seed * 0.14)) - 0.5) * 0.115;
	warp += (frost_value_noise(UV * vec2(35.0, 22.0) + melt_seed) - 0.5) * 0.018;
	float field = d + warp;
	float cleared = 1.0 - smoothstep(-0.018, 0.030, field);
	cleared *= smoothstep(0.0, 0.16, heated_warmth);
	// Persistent frost hugs the real pane edge even at full warmth.
	float edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	cleared *= smoothstep(0.015, 0.13, edge);

	// The thin wet transition follows the thaw front, not the whole blob interior.
	float wet_band = (1.0 - smoothstep(0.0, 0.055, abs(field))) * heated_warmth;
	f.x *= 1.0 - cleared;
	f.y *= 1.0 - cleared;
	f.z = max(f.z, wet_band * 0.48);

	ALBEDO = mix(frost_color(UV, f, glass_tint.rgb, frost_tint.rgb), glass_tint.rgb * 0.8, f.z * 0.5);
	ALPHA = mix(0.095, 0.995, clamp(f.x * 0.95 + f.y * 0.15, 0.0, 1.0)) + f.z * 0.12;
	ROUGHNESS = mix(mix(0.18, 0.96, f.x), 0.05, f.z);
}
