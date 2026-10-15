shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// Chunk-wide settled snow: a terrain-height grid lifted by the same depth as
// Henry's window (snow_base_depth); UV.y carries the shore fade. Ridges shade per
// pixel, so they read on a coarse grid. See docs/technical/SNOW_COVER.md.
#include "res://shaders/environment/snow/snow_surface.gdshaderinc"
#include "res://shaders/environment/stylized_shadow.gdshaderinc"
#include "res://shaders/environment/materials/painterly_surface.gdshaderinc"

// xy: window min corner, z: window size, w: 1 when the window is live.
global uniform vec4 snow_window;
uniform vec3 fresh_color : source_color = vec3(0.8, 0.83, 0.88);
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

// Settled depth here; the vertex's shore fade (UV.y) keeps the sea edge clean.
float depth_at(vec2 xz, float shore) {
	return snow_base_depth(xz, city_at(xz) * shore);
}

varying vec3 v_world;
varying vec3 v_ground_normal;
varying float v_shore;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_shore = UV.y;
	v_ground_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// Geometry carries only the smooth base, which Henry's window meets exactly;
	// ridges live in the per-pixel normal below.
	VERTEX.y += snow_base_geom(city_at(world.xz) * v_shore);
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	HFN_SHADOW_FRAGMENT(v_world);
	vec2 in_window = (v_world.xz - snow_window.xy) / max(snow_window.z, 0.001);
	bool inside = snow_window.w > 0.5 && all(greaterThan(in_window, vec2(0.0))) && all(lessThan(in_window, vec2(1.0)));
	float depth = depth_at(v_world.xz, v_shore);
	if (inside || depth < 0.012) {
		discard;
	}
	// Ridge slope from the depth function itself, not the 2 m mesh.
	float e = 0.08;
	float gx = (depth_at(v_world.xz + vec2(e, 0.0), v_shore) - depth_at(v_world.xz - vec2(e, 0.0), v_shore)) / (2.0 * e);
	float gz = (depth_at(v_world.xz + vec2(0.0, e), v_shore) - depth_at(v_world.xz - vec2(0.0, e), v_shore)) / (2.0 * e);
	vec2 ripple = snow_ripple_slope(v_world.xz, city_at(v_world.xz) * v_shore);
	vec3 n = normalize(normalize(v_ground_normal) - vec3(gx + ripple.x, 0.0, gz + ripple.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	vec3 color = fresh_color * (1.0 - snow_breakup(v_world, 5.0) * 0.03);
	color *= mix(1.0, 1.03, smoothstep(0.1, 0.4, depth));
	ALBEDO = snow_thin_tint(snow_wind_tint(color, city_at(v_world.xz) * v_shore), depth);
	ALBEDO = hfn_painterly_surface_color(ALBEDO, v_world, n, 0.42);
	ROUGHNESS = 0.85;
}


void light() {
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);
	float attenuation = hfn_stylized_shadow(ATTENUATION, LIGHT_IS_DIRECTIONAL);
	DIFFUSE_LIGHT += ndotl * attenuation * LIGHT_COLOR / PI;
}
