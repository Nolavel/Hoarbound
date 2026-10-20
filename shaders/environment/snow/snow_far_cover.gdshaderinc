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

// The city factor with a cubic B-spline (GPU Gems 2 ch. 20, four bilinear taps): smooth
// slopes for shading, so drifts read as rounded snow, not the bilinear 2 m facets.
float snow_city_smooth(vec2 xz) {
	if (wind_extent.x <= 0.0) {
		return 1.0;
	}
	vec2 uv = (xz - wind_origin) / wind_extent;
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
		return 1.0;
	}
	vec2 size = vec2(textureSize(wind_tex, 0));
	vec2 t = uv * size - 0.5;
	vec2 i = floor(t);
	vec2 f = t - i;
	vec2 w0 = (1.0 - f) * (1.0 - f) * (1.0 - f) / 6.0;
	vec2 w1 = (4.0 - 6.0 * f * f + 3.0 * f * f * f) / 6.0;
	vec2 w3 = f * f * f / 6.0;
	vec2 w2 = 1.0 - w0 - w1 - w3;
	vec2 g0 = w0 + w1;
	vec2 g1 = w2 + w3;
	vec2 h0 = (i - 0.5 + w1 / g0) / size;
	vec2 h1 = (i + 1.5 + w3 / g1) / size;
	vec4 a = texture(wind_tex, h0);
	vec4 b = texture(wind_tex, vec2(h1.x, h0.y));
	vec4 c = texture(wind_tex, vec2(h0.x, h1.y));
	vec4 d = texture(wind_tex, h1);
	vec4 w = g0.y * (g0.x * a + g1.x * b) + g1.y * (g0.x * c + g1.x * d);
	return mix(w.r, w.g, snow_storm_share) * wind_max;
}

// Settled depth with ridges; `shore` is the chunk vertex's shore fade, interpolated.
float snow_far_depth(vec2 xz, float shore) {
	return snow_base_depth(xz, snow_city_at(xz) * shore);
}

// Normal, albedo (before the painterly pass) and depth of the far cover at a pixel.
void snow_far_shade(vec3 world, vec3 ground_normal, float shore, out vec3 n, out vec3 albedo, out float depth) {
	float city = snow_city_at(world.xz) * shore;
	vec3 ridge = snow_ridge_d(world.xz, snow_wind);
	float amount = snow_ridge_amount(city);
	depth = snow_base_geom(city) + amount * ridge.x;
	// Depth slope per pixel, not from the 2 m mesh: the smooth city factor by differences,
	// the ridge analytically.
	float e = 0.25;
	float c0 = snow_city_smooth(world.xz);
	vec2 d_city = vec2(snow_city_smooth(world.xz + vec2(e, 0.0)) - c0, snow_city_smooth(world.xz + vec2(0.0, e)) - c0) * shore / e;
	float d_amount = (snow_ridge_amount(city + 0.01) - snow_ridge_amount(city - 0.01)) / 0.02;
	vec2 g = (snow_settled_depth + d_amount * ridge.x) * d_city + amount * ridge.yz;
	float gx = g.x;
	float gz = g.y;
	vec2 ripple = snow_ripple_slope(world.xz, city);
	n = normalize(normalize(ground_normal) - vec3(gx + ripple.x, 0.0, gz + ripple.y));
	vec3 color = fresh_color * snow_patch_albedo(world.xz);
	color *= mix(1.0, 1.03, smoothstep(0.1, 0.4, depth));
	albedo = snow_thin_tint(snow_wind_tint(color, city), depth);
}
