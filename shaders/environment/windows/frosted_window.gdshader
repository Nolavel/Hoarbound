// Opaque frosted windows on generated buildings: one material for every pane of a chunk, lit like
// the walls. COLOR.r = frost coverage (1 for an empty house), COLOR.g = pattern seed.
shader_type spatial;
render_mode diffuse_lambert;

#define HFN_STATIC_WORLD
#include "res://shaders/environment/windows/frost_pattern.gdshaderinc"

uniform vec3 frost_tint : source_color = vec3(0.86, 0.91, 0.95);
uniform vec3 glass_tint : source_color = vec3(0.16, 0.2, 0.24);

void frosted_window_apply(inout vec3 albedo, inout float rough, vec2 uv, vec4 color) {
	vec2 f = frost_pattern(uv, color.r, color.g);
	albedo = frost_color(uv, f, glass_tint, frost_tint);
	rough = mix(0.18, 0.96, f.x);
}

#define HFN_FRAGMENT_EXTRA frosted_window_apply(ALBEDO, ROUGHNESS, UV, COLOR);
#include "res://shaders/environment/materials/stylized_environment_body.gdshaderinc"
