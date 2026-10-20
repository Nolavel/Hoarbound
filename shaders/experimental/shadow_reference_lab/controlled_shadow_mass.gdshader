shader_type spatial;
render_mode specular_disabled, ambient_light_disabled;

// Experiment only. The physical shadow lookup and production three-tone response
// remain in the shared include. Colour mass and edge breakup are independent.
#include "res://shaders/environment/stylized_shadow.gdshaderinc"

uniform vec3 surface_color : source_color = vec3(0.80, 0.83, 0.84);
uniform vec3 shadow_pigment : source_color = vec3(0.19, 0.29, 0.36);
uniform float mass_strength : hint_range(0.0, 1.0) = 0.0;
uniform float edge_strength : hint_range(0.0, 1.0) = 0.0;

varying vec3 test_world_pos;

void vertex() {
	test_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	HFN_SHADOW_FRAGMENT(test_world_pos);
	ALBEDO = surface_color;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = max(dot(NORMAL, LIGHT), 0.0);
	float physical = clamp(ATTENUATION, 0.0, 1.0);
	// Omni/spot ATTENUATION also contains distance falloff. Keep local lights
	// unchanged so the warm lamp cannot turn its range edge into pigment.
	if (!LIGHT_IS_DIRECTIONAL) {
		DIFFUSE_LIGHT += ndl * hfn_stylized_shadow(physical, false) * LIGHT_COLOR / PI;
		return;
	}

	// Only the physical penumbra is displaced. Its world-space field is fixed
	// across frames; light distance attenuation remains intact outside this band.
	float edge_band = smoothstep(0.12, 0.32, physical)
		* (1.0 - smoothstep(0.70, 0.92, physical));
	float coarse = sin(test_world_pos.x * 2.1 + test_world_pos.z * 0.7)
		* sin(test_world_pos.z * 2.7 - test_world_pos.y * 0.6);
	float stroke = sin(test_world_pos.x * 5.1 - test_world_pos.z * 1.9);
	float adjusted = clamp(physical
		+ edge_strength * edge_band * (coarse * 0.15 + stroke * 0.04), 0.0, 1.0);
	float tone = hfn_stylized_shadow(adjusted, LIGHT_IS_DIRECTIONAL);

	// With mass_strength=0 this is the existing diffuse shadow coefficient.
	// The pigment tint changes only the shadowed light contribution, not the
	// illuminated albedo. It is deliberately a per-material experiment.
	float shade = 1.0 - smoothstep(0.18, 0.82, tone);
	vec3 painted = mix(vec3(tone), mix(vec3(tone), shadow_pigment, shade),
		mass_strength);
	DIFFUSE_LIGHT += painted * ndl * LIGHT_COLOR / PI;
}
