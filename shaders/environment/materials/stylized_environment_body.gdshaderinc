#include "res://shaders/environment/stylized_shadow.gdshaderinc"
#ifdef HFN_PAINTERLY_SURFACE
#include "res://shaders/environment/materials/painterly_surface.gdshaderinc"
#endif

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform bool use_vertex_color = false;
uniform bool use_albedo_texture = false;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_normal_texture = false;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_scale : hint_range(-16.0, 16.0) = 1.0;
// glTF packed map: roughness in G and metallic in B scale the factors above; AO in R when it is packed in.
uniform bool use_orm_texture = false;
uniform bool use_orm_ao = false;
uniform sampler2D orm_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
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

// Dissolve the TPS camera drives on Henry when it is inside his reach: only his parts near the lens go
// (head, shoulder, pack); a metre out stays whole. The grain is interleaved gradient noise (Jimenez 2014):
// pixel-fine with no repeating grid. HFN_STATIC_WORLD drops it (16 global slots per instance).
#ifndef HFN_STATIC_WORLD
instance uniform float camera_fade : hint_range(0.0, 1.0) = 0.0;
const float HFN_CAMERA_FADE_NEAR = 0.35;
const float HFN_CAMERA_FADE_FAR = 1.1;
#endif

#ifndef HFN_STATIC_WORLD
// Garments under a pack strap: the vertex colour holds how far a point is pressed in (R, of
// garment_press_max metres) and whether its normal faces out (G); garment_press turns it on.
uniform float garment_press : hint_range(0.0, 1.0) = 0.0;
uniform float garment_press_max = 0.03;
#include "res://shaders/environment/materials/garment_frost.gdshaderinc"
#endif

varying vec3 stylized_noise_pos;
varying vec3 stylized_world_normal;
#ifndef HFN_STATIC_WORLD
varying vec3 stylized_model_pos;
#endif

void vertex() {
	// HFN_VERTEX_EXTRA: optional per-family vertex step (e.g. snow_stems lifts stems with the snow).
#ifdef HFN_VERTEX_EXTRA
	HFN_VERTEX_EXTRA
#endif
#ifndef HFN_STATIC_WORLD
	if (garment_press > 0.0) {
		VERTEX -= NORMAL * (COLOR.g > 0.5 ? 1.0 : -1.0) * COLOR.r * garment_press_max * garment_press;
	}
#endif
	stylized_noise_pos = shadow_noise_in_model_space ? VERTEX : (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	stylized_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
#ifndef HFN_STATIC_WORLD
	stylized_model_pos = VERTEX;
#endif
}

void fragment() {
#ifndef HFN_STATIC_WORLD
	if (camera_fade > 0.0) {
		float near_part = 1.0 - smoothstep(HFN_CAMERA_FADE_NEAR, HFN_CAMERA_FADE_FAR, length(VERTEX));
		float grain = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (camera_fade * near_part > grain) {
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
#ifdef HFN_PAINTERLY_SURFACE
	ALBEDO = hfn_painterly_surface_color(ALBEDO, stylized_noise_pos, stylized_world_normal, 1.0);
#endif
	ROUGHNESS = roughness;
	METALLIC = metallic;
	if (use_orm_texture) {
		vec3 orm = texture(orm_texture, uv).rgb;
		ROUGHNESS = roughness * orm.g;
		METALLIC = metallic * orm.b;
		if (use_orm_ao) {
			AO = orm.r;
		}
	}
	// Static world geometry never takes a normal texture (make_static); leaving NORMAL_MAP out keeps its
	// meshes free of tangents (chunks are generated without them).
#ifndef HFN_STATIC_WORLD
	if (use_normal_texture) {
		NORMAL_MAP = texture(normal_texture, uv).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
#endif
#ifndef HFN_STATIC_WORLD
	if (garment_frost > 0.0) {
		float frost_metal = METALLIC;
		hfn_apply_garment_frost(ALBEDO, ROUGHNESS, frost_metal, stylized_model_pos, stylized_world_normal, METALLIC);
		METALLIC = frost_metal;
	}
#endif
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
	float spec_power = mix(128.0, 4.0, ROUGHNESS);
	float spec = pow(max(dot(NORMAL, half_dir), 0.0), spec_power);
	float spec_gain = mix(0.05, 0.24, METALLIC) * (1.0 - ROUGHNESS);
	SPECULAR_LIGHT += spec * spec_gain * attenuation * LIGHT_COLOR;
}
