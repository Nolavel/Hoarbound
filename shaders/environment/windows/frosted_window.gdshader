// Opaque frosted windows on generated buildings: one material for every pane of a chunk, lit like
// the walls. COLOR.r = frost coverage (1 for an empty house), COLOR.g = pattern seed.
shader_type spatial;
render_mode diffuse_lambert;

#define HFN_STATIC_WORLD
// Only its hash, noise and pane-size helpers are used; the frost comes from the baked tiles.
#include "res://shaders/environment/windows/frost_pattern.gdshaderinc"
#include "res://shaders/environment/windows/frost_tiles.gdshaderinc"

uniform vec3 frost_tint : source_color = vec3(0.93, 0.96, 0.99);
uniform vec3 hoar_tint : source_color = vec3(0.74, 0.80, 0.86);
uniform vec3 glass_tint : source_color = vec3(0.16, 0.2, 0.24);
// Sash window: a painted frame round the pane and a meeting rail across its middle, in pane UV.
uniform vec3 frame_color : source_color = vec3(0.30, 0.28, 0.26);
uniform float frame_width : hint_range(0.0, 0.2) = 0.06;
uniform float rail_width : hint_range(0.0, 0.1) = 0.025;

void frosted_window_apply(inout vec3 albedo, inout float rough, vec2 uv, vec4 color, vec3 vertex) {
	// The same frost as the see-through landmark glass, without its thaw: these houses stay cold.
	vec2 pane = frost_pane_m(uv, vertex);
	vec2 m = uv * pane;
	vec4 cover = frost_cover(m, pane, color.r, color.g, frost_order(m, pane, color.g));
	float thick = cover.x * 0.95 + cover.y * 0.42 + cover.w;
	float scatter = 1.0 - exp(-thick * 2.7);
	vec3 frost = mix(hoar_tint, frost_tint, max(clamp(cover.x * 1.15 + cover.y * 0.35, 0.0, 1.0), smoothstep(0.5, 1.3, thick) * 0.6));
	albedo = mix(glass_tint, frost, scatter);
	rough = mix(0.18, 0.96, scatter);
	float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	float frame = max(1.0 - step(frame_width, edge), 1.0 - step(rail_width, abs(uv.y - 0.5)));
	albedo = mix(albedo, frame_color, frame);
	rough = mix(rough, 0.8, frame);
}

#define HFN_FRAGMENT_EXTRA frosted_window_apply(ALBEDO, ROUGHNESS, UV, COLOR, VERTEX);
#include "res://shaders/environment/materials/stylized_environment_body.gdshaderinc"
