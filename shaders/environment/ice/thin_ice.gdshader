shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// Frozen-sea look plus load cracks and holes from IceCrackPresenter's window maps.
// Cracks grow by revealing a fixed spoke-and-ring pattern out from the load point.

#include "res://shaders/environment/stylized_shadow.gdshaderinc"
#include "res://shaders/environment/ice/frozen_sea_surface.gdshaderinc"

// R growth 0..1, BA crack origin inside the tile (0..1).
uniform sampler2D crack_map : filter_nearest, repeat_disable;
// R hole flag, GB hole centre inside the tile (0..1).
uniform sampler2D hole_map : filter_nearest, repeat_disable;
uniform vec2 window_origin_tile = vec2(0.0);
uniform float window_tiles = 16.0;
uniform float tile_size = 4.0;
uniform float hole_base_radius = 1.05;
// How far cracks reach at full growth, as a share of the tile size.
uniform float crack_reach = 0.9;
uniform vec3 crack_color : source_color = vec3(0.80, 0.87, 0.93);
uniform vec3 seep_color : source_color = vec3(0.10, 0.16, 0.22);

varying vec3 world_pos;

float hash1(float n) {
	return fract(sin(n * 91.3458) * 47453.5453);
}

float tile_hash(vec2 t) {
	return fract(sin(dot(t, vec2(12.9898, 78.233))) * 43758.5453);
}

// Anti-aliased line of half-width w at distance d; px is metres per pixel.
float line_mask(float d, float w, float px) {
	float we = max(w, px * 0.8);
	return (1.0 - smoothstep(we * 0.5, we, d)) * (w / we);
}

// Mirrors IceHoleShape.radius_at: integer phases keep CPU and GPU on one outline.
float hole_radius(vec2 t, float angle) {
	float a = mod(t.x * 7.0 + t.y * 13.0, 17.0) / 17.0 * TAU;
	float b = mod(t.x * 11.0 + t.y * 5.0, 23.0) / 23.0 * TAU;
	float broad = 0.14 * sin(3.0 * angle + a) + 0.08 * sin(5.0 * angle + b);
	float jagged = 0.045 * sin(9.0 * angle + a * 2.0) + 0.03 * sin(14.0 * angle + b * 3.0);
	return hole_base_radius * (1.0 + broad + jagged);
}

// x: crack line, y: water seeping into the main spokes, z: wet halo.
vec3 crack_field(vec2 p, float growth, float seed, float px) {
	float reach = growth * crack_reach * tile_size;
	float r = length(p);
	if (r > reach + 0.05) {
		return vec3(0.0);
	}
	float theta = atan(p.y, p.x);
	float spokes = 7.0 + floor(hash1(seed) * 4.0);
	float sector = TAU / spokes;
	float line = 0.0;
	float seep = 0.0;
	for (int k = 0; k < 10; k++) {
		float fk = float(k);
		if (fk >= spokes) {
			break;
		}
		float hk = hash1(seed + fk * 1.37);
		float length_k = reach * (0.55 + 0.45 * hash1(seed + fk * 2.71 + 0.5));
		if (r > length_k) {
			continue;
		}
		float base_angle = (fk + 0.35 * (hk - 0.5)) * sector;
		float d_theta = theta - base_angle;
		d_theta = d_theta - TAU * floor((d_theta + PI) / TAU);
		if (cos(d_theta) <= 0.0) {
			continue;
		}
		float wander = (0.10 * sin(r * 2.1 + hk * 6.28) + 0.04 * sin(r * 6.3 + hk * 17.0)) * smoothstep(0.0, 0.5, r);
		float d = abs(r * sin(d_theta) - wander);
		float w = mix(0.016, 0.006, r / max(length_k, 0.001));
		float tip = 1.0 - smoothstep(length_k * 0.85, length_k, r);
		line = max(line, line_mask(d, w, px) * tip);
		seep = max(seep, line_mask(d, w * 0.35, px) * tip);
	}
	for (int j = 1; j <= 3; j++) {
		float fj = float(j);
		float ring = (0.35 + 0.6 * fj) * (0.8 + 0.4 * hash1(seed + fj * 5.3)) * tile_size / 4.0;
		if (ring > reach * 0.85) {
			break;
		}
		float s = floor(mod(theta + PI, TAU) / sector);
		if (hash1(seed + s * 3.1 + fj * 13.0) < 0.45) {
			continue;
		}
		float wobble = ring * (1.0 + 0.08 * sin(4.0 * theta + seed * 6.28));
		line = max(line, line_mask(abs(r - wobble), 0.008, px) * 0.8);
	}
	float crushed = (1.0 - smoothstep(0.0, 0.3 * growth, r)) * 0.5 * growth;
	line = max(line, crushed);
	seep *= smoothstep(0.55, 0.9, growth);
	float wet = (1.0 - smoothstep(0.0, reach * 0.6, r)) * smoothstep(0.6, 1.0, growth) * 0.35;
	return vec3(line, seep, wet);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	HFN_SHADOW_FRAGMENT(world_pos);
	float px = length(fwidth(world_pos.xz));
	vec2 home = floor(world_pos.xz / tile_size);
	vec3 marks = vec3(0.0);
	float rim_d = 1000.0;
	for (int dz = -1; dz <= 1; dz++) {
		for (int dx = -1; dx <= 1; dx++) {
			vec2 t = home + vec2(float(dx), float(dz));
			vec2 cell = t - window_origin_tile;
			if (cell.x < 0.0 || cell.y < 0.0 || cell.x >= window_tiles || cell.y >= window_tiles) {
				continue;
			}
			ivec2 texel = ivec2(cell);
			vec4 c = texelFetch(crack_map, texel, 0);
			if (c.r > 0.0) {
				vec2 origin = (t + c.ba) * tile_size;
				marks = max(marks, crack_field(world_pos.xz - origin, c.r, tile_hash(t), px));
			}
			vec4 h = texelFetch(hole_map, texel, 0);
			if (h.r > 0.5) {
				vec2 offset = world_pos.xz - (t + h.gb) * tile_size;
				float d = length(offset) - hole_radius(t, atan(offset.y, offset.x));
				if (d < 0.0) {
					discard;
				}
				rim_d = min(rim_d, d);
				marks = max(marks, crack_field(offset, 1.0, tile_hash(t + vec2(31.0, 17.0)), px));
			}
		}
	}
	vec3 base = FROZEN_SEA_ALBEDO * (1.0 - marks.z);
	vec3 albedo = mix(base, crack_color, marks.x);
	albedo = mix(albedo, seep_color, marks.y);
	// Hole rim: a thin bright broken edge, then a band of wet ice darkening outwards.
	float wet_band = 1.0 - smoothstep(0.04, 0.28, rim_d);
	float broken_edge = 1.0 - smoothstep(0.0, 0.04, rim_d);
	albedo = mix(albedo, seep_color * 1.3, wet_band * 0.75);
	albedo = mix(albedo, crack_color, broken_edge * 0.85);
	ALBEDO = albedo;
	ROUGHNESS = mix(FROZEN_SEA_ROUGHNESS, 0.62, marks.x);
	METALLIC = FROZEN_SEA_METALLIC;
}

void light() {
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);
	float attenuation = hfn_stylized_shadow(ATTENUATION, LIGHT_IS_DIRECTIONAL);
	DIFFUSE_LIGHT += ndotl * attenuation * LIGHT_COLOR / PI;
}
