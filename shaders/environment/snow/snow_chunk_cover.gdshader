shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// Chunk-wide settled snow: a terrain-height grid lifted by the same depth as
// Henry's window (snow_base_geom); UV.y carries the shore fade. Ridges shade per
// pixel, so they read on a coarse grid. See docs/technical/SNOW_COVER.md.
#include "res://shaders/environment/snow/snow_surface.gdshaderinc"
#include "res://shaders/environment/snow/snow_far_cover.gdshaderinc"
#include "res://shaders/environment/stylized_shadow.gdshaderinc"
#include "res://shaders/environment/materials/painterly_surface.gdshaderinc"

// Capture-only height readout (tools/runtime/capture_snow_surface.gd).
uniform bool debug_height = false;
varying vec3 v_world;
varying vec3 v_ground_normal;
varying float v_shore;
varying vec3 v_glint_n;
varying float v_glint;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_shore = UV.y;
	v_ground_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// Settled depth with the wind's ridges at the 2 m vertices; snow_ground's outer band draws the same triangles.
	VERTEX.y += snow_base_depth(world.xz, snow_city_at(world.xz) * v_shore);
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	HFN_SHADOW_FRAGMENT(v_world);
	bool inside = snow_lod.w > 0.5 && snow_lod_distance(v_world.xz) < snow_lod.z - SNOW_LOD_OVERLAP_M;
	vec3 n;
	vec3 albedo;
	float depth;
	snow_far_shade(v_world, v_ground_normal, v_shore, n, albedo, depth);
	if (inside || depth < 0.012) {
		discard;
	}
	float footprint = length(fwidth(v_world.xz));
	snow_apply_grain(n, albedo, v_world.xz, footprint, 1.0);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = hfn_painterly_surface_color(albedo, v_world, vec3(0.0, 1.0, 0.0), 0.38);
	ROUGHNESS = 0.9;
	SPECULAR = 0.3;
	vec4 facet = snow_glint_facet(v_world.xz, n, footprint);
	v_glint_n = normalize((VIEW_MATRIX * vec4(facet.xyz, 0.0)).xyz);
	v_glint = facet.w;
	if (debug_height) {
		ALBEDO = vec3(0.0);
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
		EMISSION = snow_debug_height(v_world.y);
	}
}


void light() {
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);
	float attenuation = hfn_stylized_shadow(ATTENUATION, LIGHT_IS_DIRECTIONAL);
	DIFFUSE_LIGHT += ndotl * attenuation * LIGHT_COLOR / PI;
	SPECULAR_LIGHT += snow_glint_light(v_glint_n, v_glint, LIGHT, VIEW) * attenuation * LIGHT_COLOR;
}
