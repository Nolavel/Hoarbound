shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// Legacy showcase material retained for TestScene. Production shader families
// use the same shared contract directly rather than replacing their materials.
#include "res://shaders/environment/stylized_shadow.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_albedo_texture = false;
uniform vec4 albedo_tint : source_color = vec4(0.64, 0.68, 0.72, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.92;
uniform bool use_world = true;

varying vec3 sample_position;

void vertex() {
	sample_position = use_world
		? (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz
		: VERTEX;
}

void fragment() {
	HFN_SHADOW_FRAGMENT(sample_position);
	vec4 base = albedo_tint;
	if (use_albedo_texture) {
		base *= texture(albedo_texture, UV);
	}
	ALBEDO = base.rgb;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}

void light() {
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);
	float attenuation = hfn_stylized_shadow(ATTENUATION, LIGHT_IS_DIRECTIONAL);
	DIFFUSE_LIGHT += ndotl * attenuation * LIGHT_COLOR / PI;
}
