// The streamed chunk cover's surface and shading, shared by snow_chunk_cover and the
// outer band of snow_ground so both draw it bit for bit. See docs/technical/SNOW_COVER.md.
// Needs snow_surface.gdshaderinc first.

// Baked city wind field (R prevailing, G storm).
uniform sampler2D wind_tex : filter_linear, repeat_disable;
uniform vec2 wind_origin = vec2(0.0);
uniform vec2 wind_extent = vec2(0.0);
uniform float wind_max = 2.5;
uniform vec3 fresh_color : source_color = vec3(0.8, 0.83, 0.88);

float snow_city_at(vec2 xz) {
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

// Settled depth with ridges; `shore` is the chunk vertex's shore fade, interpolated.
float snow_far_depth(vec2 xz, float shore) {
	return snow_base_depth(xz, snow_city_at(xz) * shore);
}

// Normal, albedo (before the painterly pass) and depth of the far cover at a pixel.
void snow_far_shade(vec3 world, vec3 ground_normal, float shore, out vec3 n, out vec3 albedo, out float depth) {
	depth = snow_far_depth(world.xz, shore);
	// Ridge slope from the depth function itself, not the 2 m mesh.
	float e = 0.08;
	float gx = (snow_far_depth(world.xz + vec2(e, 0.0), shore) - snow_far_depth(world.xz - vec2(e, 0.0), shore)) / (2.0 * e);
	float gz = (snow_far_depth(world.xz + vec2(0.0, e), shore) - snow_far_depth(world.xz - vec2(0.0, e), shore)) / (2.0 * e);
	float city = snow_city_at(world.xz) * shore;
	vec2 ripple = snow_ripple_slope(world.xz, city);
	n = normalize(normalize(ground_normal) - vec3(gx + ripple.x, 0.0, gz + ripple.y));
	vec3 color = fresh_color * (1.0 - snow_breakup(world, 5.0) * 0.03);
	color *= mix(1.0, 1.03, smoothstep(0.1, 0.4, depth));
	albedo = snow_thin_tint(snow_wind_tint(color, city), depth);
}
