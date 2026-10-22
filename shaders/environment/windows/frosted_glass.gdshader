// See-through glass in real window openings (authored buildings such as 727 Fort St). Per vertex:
// COLOR.r = the pane's frost coverage in the cold, COLOR.g = 1 for a heated room, COLOR.b = seed.
// Warmth of the two rooms comes from the shelter's thermal zones; a warmed room clears to warm_coverage.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_prepass_alpha;

#include "res://shaders/environment/windows/frost_pattern.gdshaderinc"

uniform vec4 frost_tint : source_color = vec4(0.88, 0.94, 0.98, 1.0);
uniform vec4 glass_tint : source_color = vec4(0.62, 0.76, 0.86, 1.0);
uniform float heated_warmth : hint_range(0.0, 1.0) = 0.0;
uniform float unheated_warmth : hint_range(0.0, 1.0) = 0.0;
uniform float warm_coverage : hint_range(0.0, 1.0) = 0.2;
// Drawn afresh each world load (the frost) and each time the room starts to warm (the thaw's path).
uniform float growth_seed = 0.0;
uniform float melt_seed = 0.0;

void fragment() {
	float warmth = COLOR.g > 0.5 ? heated_warmth : unheated_warmth;
	// A warmed room clears from the centre until warm_coverage of the frost is left.
	vec3 f = frost_pattern(UV, frost_pane_m(UV, VERTEX), COLOR.r, warmth * (1.0 - warm_coverage), COLOR.b + growth_seed, melt_seed + COLOR.b);
	ALBEDO = mix(frost_color(UV, f, glass_tint.rgb, frost_tint.rgb), glass_tint.rgb * 0.8, f.z * 0.5);
	ALPHA = mix(0.095, 0.995, clamp(f.x * 0.95 + f.y * 0.15, 0.0, 1.0)) + f.z * 0.12;
	ROUGHNESS = mix(mix(0.18, 0.96, f.x), 0.05, f.z);
}
