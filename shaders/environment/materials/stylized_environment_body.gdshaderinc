#include "res://shaders/environment/stylized_shadow.gdshaderinc"

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform bool use_vertex_color = false;
uniform bool use_albedo_texture = false;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_normal_texture = false;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_scale : hint_range(-16.0, 16.0) = 1.0;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy : hint_range(0.0, 16.0) = 0.0;
// Characters: rim on the lit silhouette edge, a shorter shadow-lookup offset for
// thin limbs, and shadow noise in model space so it rides with the body.
uniform float rim_strength : hint_range(0.0, 2.0) = 0.0;
uniform float rim_power : hint_range(1.0, 8.0) = 3.5;
uniform float shadow_offset_scale : hint_range(0.0, 1.0) = 1.0;
uniform bool shadow_noise_in_model_space = false;

// Screen-door fade the TPS camera drives on Henry when it is inside his reach.
// Only his parts near the camera go (head, shoulder, pack); a metre out stays whole.
// HFN_STATIC_WORLD drops it: each instance uniform costs every instance 16 global slots.
#ifndef HFN_STATIC_WORLD
instance uniform float camera_fade : hint_range(0.0, 1.0) = 0.0;
const float HFN_CAMERA_FADE_NEAR = 0.35;
const float HFN_CAMERA_FADE_FAR = 1.1;
const float HFN_BAYER4[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
#endif

varying vec3 stylized_noise_pos;

void vertex() {
	// HFN_VERTEX_EXTRA: optional per-family vertex step (e.g. snow_stems lifts stems with the snow).
#ifdef HFN_VERTEX_EXTRA
	HFN_VERTEX_EXTRA
#endif
	stylized_noise_pos = shadow_noise_in_model_space ? VERTEX : (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
#ifndef HFN_STATIC_WORLD
	if (camera_fade > 0.0) {
		float near_part = 1.0 - smoothstep(HFN_CAMERA_FADE_NEAR, HFN_CAMERA_FADE_FAR, length(VERTEX));
		ivec2 cell = ivec2(FRAGCOORD.xy) & ivec2(3);
		if (camera_fade * near_part * 16.0 > HFN_BAYER4[cell.y * 4 + cell.x] + 0.5) {
			discard;
		}
	}
#endif
	HFN_SHADOW_FRAGMENT_SCALED(stylized_noise_pos, shadow_offset_scale);
	vec2 uv = UV * uv_scale + uv_offset;
	vec4 base = albedo_color;
	if (use_vertex_color) {
		base *= COLOR;
	}
	if (use_albedo_texture) {
		base *= texture(albedo_texture, uv);
	}
	ALBEDO = base.rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	if (use_normal_texture) {
		NORMAL_MAP = texture(normal_texture, uv).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
	EMISSION = emission_color * emission_energy;
	// HFN_FRAGMENT_EXTRA: optional per-family surface step (e.g. tree_snow lays snow on branch tops).
#ifdef HFN_FRAGMENT_EXTRA
	HFN_FRAGMENT_EXTRA
#endif
}

void light() {
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);
	float attenuation = hfn_stylized_shadow(ATTENUATION, LIGHT_IS_DIRECTIONAL);
	DIFFUSE_LIGHT += ndotl * attenuation * LIGHT_COLOR / PI;
	if (rim_strength > 0.0) {
		float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
		float lit_side = smoothstep(-0.2, 0.4, dot(NORMAL, LIGHT));
		DIFFUSE_LIGHT += fresnel * lit_side * rim_strength * attenuation * LIGHT_COLOR / PI;
	}

	// Cheap restrained specular keeps metal/glass-adjacent props readable
	// without reintroducing the built-in PBR path that bypasses our light().
	vec3 half_dir = normalize(LIGHT + VIEW);
	float spec_power = mix(128.0, 4.0, roughness);
	float spec = pow(max(dot(NORMAL, half_dir), 0.0), spec_power);
	float spec_gain = mix(0.05, 0.24, metallic) * (1.0 - roughness);
	SPECULAR_LIGHT += spec * spec_gain * attenuation * LIGHT_COLOR;
}
