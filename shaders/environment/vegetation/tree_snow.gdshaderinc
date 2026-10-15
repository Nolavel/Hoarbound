// Snow that settles on trees: on the up-facing tops of fronds, limbs and twigs, never on the
// vertical trunk. Cover follows the live snow_cover and the world-up normal, as snow_prop does;
// rime creeps over steep bark with frost_amount, on the windward side only. Reads snow state,
// never writes it.
#include "res://shaders/environment/snow/snow_surface.gdshaderinc"

uniform vec3 tree_snow_color : source_color = vec3(0.80, 0.83, 0.88);
uniform float tree_snow_roughness : hint_range(0.0, 1.0) = 0.85;
// Wider band on curved limbs, so the snow line follows the branch instead of cutting it.
uniform float tree_snow_softness : hint_range(0.01, 0.5) = 0.12;
// How much of the settling snow this surface keeps: smooth drooping fronds shed some.
uniform float tree_snow_hold : hint_range(0.0, 1.0) = 1.0;
uniform float tree_rime_strength : hint_range(0.0, 1.0) = 0.3;

void tree_snow_apply(inout vec3 albedo, inout float rough, vec3 view_normal, vec3 view_pos, mat4 inv_view) {
	vec3 world_normal = normalize((inv_view * vec4(view_normal, 0.0)).xyz);
	vec3 world_pos = (inv_view * vec4(view_pos, 1.0)).xyz;
	float settled = snow_weight(world_normal, world_pos, tree_snow_softness) * tree_snow_hold;
	// Rime builds on the faces the wind blows onto (snow_wind points downwind).
	vec2 wind = length(snow_wind) > 0.001 ? normalize(snow_wind) : vec2(0.0, 1.0);
	vec2 side = length(world_normal.xz) > 0.001 ? normalize(world_normal.xz) : vec2(0.0);
	float windward = smoothstep(0.0, 0.7, dot(side, -wind));
	float rime = frost_weight(world_normal, world_pos, 0.5) * windward * tree_rime_strength;
	float cover = clamp(max(settled, rime), 0.0, 1.0);
	albedo = mix(albedo, tree_snow_color, cover);
	rough = mix(rough, tree_snow_roughness, cover);
}
