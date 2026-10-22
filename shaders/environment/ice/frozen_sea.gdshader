shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

#include "res://shaders/environment/stylized_shadow.gdshaderinc"
#include "res://shaders/environment/ice/frozen_sea_surface.gdshaderinc"

// Off for Reality water polygons, which are already the measured sea outline.
uniform bool use_ocean_mask = true;
uniform sampler2D ocean_mask : filter_nearest, repeat_disable;
uniform vec2 world_origin;
uniform vec2 world_size;
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	HFN_SHADOW_FRAGMENT(world_pos);
	if (use_ocean_mask) {
		vec2 uv = (world_pos.xz - world_origin) / world_size;
		if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
			discard;
		}
		if (texture(ocean_mask, uv).r < 0.5) {
			discard;
		}
	}
	ALBEDO = FROZEN_SEA_ALBEDO;
	ROUGHNESS = FROZEN_SEA_ROUGHNESS;
	METALLIC = FROZEN_SEA_METALLIC;
}

void light() {
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);
	float attenuation = hfn_stylized_shadow(ATTENUATION, LIGHT_IS_DIRECTIONAL);
	DIFFUSE_LIGHT += ndotl * attenuation * LIGHT_COLOR / PI;
}
