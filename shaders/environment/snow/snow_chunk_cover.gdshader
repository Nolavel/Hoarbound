shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// Chunk-wide settled snow: a terrain-height grid lifted by the same depth as
// Henry's window (snow_base_depth); UV.y carries the shore fade. Ridges shade per
// pixel, so they read on a coarse grid. See docs/technical/SNOW_COVER.md.
#include "res://shaders/environment/snow/snow_surface.gdshaderinc"
#include "res://shaders/environment/stylized_shadow.gdshaderinc"
#include "res://shaders/environment/materials/painterly_surface.gdshaderinc"

// xy: current window min corner, z: size, w: 1 when live.
global uniform vec4 snow_window;
// A retained previous high-detail window. This is a regular material uniform set
// on SnowChunkCover's shared material; it keeps the coarse cover out of the trail.
uniform vec4 trail_window = vec4(0.0);
uniform vec3 fresh_color : source_color = vec3(0.8, 0.83, 0.88);
// Capture-only ownership overlay. Runtime keeps this false.
uniform bool debug_lod_ownership = false;
// Fixed-world 3-LOD tiles own pixels near Henry; legacy recenter windows have
// no fragment ownership while this mode is enabled. Exactly complementary
// world-space dither in snow_world_tiles_production.gdshader.
uniform bool world_tiles_active = false;
// One shader for streamed cover and immutable 3-LOD tiles. The original
// split material produced a clearly visible circular colour/normal halo.
uniform bool is_world_tile = false;
uniform sampler2D deformation : filter_linear, repeat_disable;
uniform vec2 tile_origin = vec2(0.0);
uniform float tile_m = 3.2;
uniform bool debug_height = false;
uniform float reference_y = 0.0;
uniform vec3 packed_color : source_color = vec3(0.5, 0.56, 0.68);
float world_tile_detail(vec2 world_xz) {
	return 1.0 - smoothstep(12.0, 17.0, distance(world_xz, snow_player_xz));
}
// Same GPU-height witness encoding as SnowShell; render-only, default off.
uniform bool debug_gpu_height = false;
uniform float debug_height_reference = 0.0;
// Capture-only scale. Production rendering never uses this diagnostic value.
uniform float debug_height_gain = 0.08;
// Baked city wind field (R prevailing, G storm), sampled per pixel so lee tongues
// and scoured streets shade at 2 m even far from the mesh vertices.
uniform sampler2D wind_tex : filter_linear, repeat_disable;
uniform vec2 wind_origin = vec2(0.0);
uniform vec2 wind_extent = vec2(0.0);
uniform float wind_max = 2.5;
float city_at(vec2 xz) {
	if (wind_extent.x <= 0.0) {
		return 1.0;
	}
	vec2 uv = (xz - wind_origin) / wind_extent;
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
		return 1.0;
	}
	vec4 w = texture(wind_tex, uv);
	return mix(w.r, w.g, snow_storm_share) * wind_max;
}

float depth_at(vec2 xz, float shore) {
	return snow_base_depth(xz, city_at(xz) * shore);
}

varying vec3 v_world;
varying vec3 v_ground_normal;
varying float v_shore;
varying float tile_compression;
varying float tile_displacement;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_shore = UV.y;
	v_ground_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (is_world_tile) {
		// Same baked source 2m triangle at any fine/medium/coarse LOD;
		// UV2 packs prevailing and storm vertex snow factors times shore.
		VERTEX.y += snow_settled_depth * mix(UV2.x, UV2.y, snow_storm_share);
		vec2 sample_uv = clamp((world.xz - tile_origin) / tile_m, vec2(0.0), vec2(1.0));
		sample_uv = sample_uv * (32.0 / 33.0) + vec2(0.5 / 33.0);
		vec4 print_state = texture(deformation, sample_uv);
		tile_compression = max(print_state.r, 0.0);
		tile_displacement = max(print_state.g, 0.0);
		VERTEX.y += tile_displacement - tile_compression;
	} else {
		VERTEX.y += snow_base_geom(city_at(world.xz) * v_shore);
		tile_compression = 0.0;
		tile_displacement = 0.0;
	}
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

bool inside_window(vec2 xz, vec4 window) {
	if (window.w < 0.5) {
		return false;
	}
	vec2 uv = (xz - window.xy) / max(window.z, 0.001);
	return all(greaterThan(uv, vec2(0.0))) && all(lessThan(uv, vec2(1.0)));
}

void fragment() {
	HFN_SHADOW_FRAGMENT(v_world);
	bool in_live = inside_window(v_world.xz, snow_window);
	bool in_trail = inside_window(v_world.xz, trail_window);
	float depth = depth_at(v_world.xz, v_shore);
	if (depth < 0.012) {
		discard;
	}
	if (is_world_tile) {
		if (snow_trail_dither(v_world.xz) >= world_tile_detail(v_world.xz)) {
			discard;
		}
	} else if (world_tiles_active) {
		if (snow_trail_dither(v_world.xz) < world_tile_detail(v_world.xz)) {
			discard;
		}
	} else {
		if (in_live) {
			discard;
		}
		// Legacy retained window handoff (rollback).
		if (in_trail && snow_trail_dither(v_world.xz) <= snow_trail_detail(v_world.xz)) {
			discard;
		}
	}
	// Same world-space normal and snow tint as the fine shell's outer rim.
	// The displaced world position already contains the base snow geometry.
	vec3 geo = normalize(cross(dFdy(v_world), dFdx(v_world)));
	float city = city_at(v_world.xz) * v_shore;
	vec3 n = snow_outer_normal(geo, v_world.xz, city);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = hfn_painterly_surface_color(
		snow_outer_albedo(fresh_color, v_world, depth, city), v_world, n, 0.38
	);
	ROUGHNESS = 0.85;
	if (is_world_tile) {
		float packed = smoothstep(0.007, 0.12, tile_compression);
		float rim = smoothstep(0.006, 0.04, tile_displacement);
		ALBEDO = mix(ALBEDO, packed_color, packed * 0.72);
		ALBEDO *= 1.0 + rim * 0.055;
		ROUGHNESS = mix(0.85, 0.72, packed);
	}
	if (is_world_tile && debug_height) {
		// The actual deformation applied to VERTEX.y, in metres: black-red
		// depression, light-red raised rim, neutral for untouched settled snow.
		// Unlike absolute Y this is readable on a level city street.
		float displacement_m = tile_displacement - tile_compression;
		ALBEDO = vec3(0.0);
		EMISSION = vec3(clamp(0.5 + displacement_m * 3.5, 0.0, 1.0), 0.32, 0.90);
		ROUGHNESS = 1.0;
		NORMAL = normalize((VIEW_MATRIX * vec4(vec3(0.0, 1.0, 0.0), 0.0)).xyz);
	} else if (debug_gpu_height) {
		ALBEDO = vec3(0.0);
		EMISSION = vec3(clamp(0.5 + (v_world.y - debug_height_reference) * debug_height_gain, 0.0, 1.0), 0.32, 0.90);
		ROUGHNESS = 1.0;
		NORMAL = normalize((VIEW_MATRIX * vec4(vec3(0.0, 1.0, 0.0), 0.0)).xyz);
	} else if (debug_lod_ownership) {
		vec3 owner = vec3(0.12, 0.82, 0.28);
		ALBEDO = owner;
		ROUGHNESS = 1.0;
		EMISSION = owner * 0.12;
		NORMAL = normalize((VIEW_MATRIX * vec4(v_ground_normal, 0.0)).xyz);
	}
}

void light() {
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);
	vec3 attenuation = hfn_shadow_style_response(ATTENUATION, LIGHT_IS_DIRECTIONAL);
	DIFFUSE_LIGHT += ndotl * attenuation * LIGHT_COLOR / PI;
}
