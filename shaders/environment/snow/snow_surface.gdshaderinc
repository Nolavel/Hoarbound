// Shared snow and rime response for any spatial material, terrain-agnostic.
// Globals written by SnowPresentationSystem; see docs/technical/SNOW_COVER.md.

global uniform float snow_cover;
global uniform float frost_amount;

// Cheap world-space value noise, so no texture is required to break up edges.
float snow_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float snow_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(snow_hash(i), snow_hash(i + vec2(1.0, 0.0)), u.x),
		mix(snow_hash(i + vec2(0.0, 1.0)), snow_hash(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

// Two octaves of noise over a world XZ position, 0..1.
float snow_breakup(vec3 world_pos, float scale) {
	vec2 p = world_pos.xz * scale;
	return snow_noise(p) * 0.65 + snow_noise(p * 3.1 + 17.0) * 0.35;
}

// Settled snow on up-facing surfaces. More cover reaches steeper slopes.
float snow_weight(vec3 world_normal, vec3 world_pos, float softness) {
	float up = dot(normalize(world_normal), vec3(0.0, 1.0, 0.0));
	float threshold = mix(0.97, 0.35, clamp(snow_cover, 0.0, 1.0));
	float jitter = (snow_breakup(world_pos, 1.7) - 0.5) * 0.25;
	return smoothstep(threshold - softness, threshold + softness, up + jitter);
}

// How close a point on a box is to its edges and base, 0 mid-face to 1 on an
// edge. Rime needs something to grow from; it starts at corners, not mid-wall.
float box_edge_factor(vec3 local_pos, vec3 half_extents, float edge_width, float base_height) {
	vec3 d = max(half_extents - abs(local_pos), vec3(0.0));
	float lo = min(d.x, min(d.y, d.z));
	float hi = max(d.x, max(d.y, d.z));
	float to_edge = d.x + d.y + d.z - lo - hi;
	float edge = 1.0 - smoothstep(0.0, edge_width, to_edge);
	float base = 1.0 - smoothstep(0.0, base_height, local_pos.y + half_extents.y);
	return max(edge, base * 0.85);
}

// Rime on steep faces, growing inward from edges as frost_amount rises. `edge`
// is 1 on edges, corners and cavities; noise only breaks up the growth front.
float frost_weight(vec3 world_normal, vec3 world_pos, float edge) {
	float up = abs(dot(normalize(world_normal), vec3(0.0, 1.0, 0.0)));
	float steep = smoothstep(0.25, 0.85, 1.0 - up);
	vec2 wall_plane = vec2(world_pos.x + world_pos.z, world_pos.y);
	float grain = snow_noise(wall_plane * 7.0) * 0.6 + snow_noise(wall_plane * 19.0 + 3.0) * 0.4;
	float reach = clamp(frost_amount, 0.0, 1.0);
	float front = edge + (grain - 0.5) * 0.35;
	float threshold = 1.0 - reach * 1.3;
	return steep * smoothstep(threshold, threshold + 0.2, front);
}


// Wind ridges on settled snow. SnowField.ridge() mirrors this bit for bit, so the
// detailed window and the chunk-wide cover draw the same drifts.
float snow_ihash(ivec2 c) {
	uint h = uint(c.x) * 374761393u + uint(c.y) * 668265263u;
	h = (h ^ (h >> 13u)) * 1274126177u;
	h ^= h >> 16u;
	return float(h & 65535u) / 65535.0;
}

float snow_vnoise(vec2 p) {
	vec2 fl = floor(p);
	ivec2 i = ivec2(fl);
	vec2 f = p - fl;
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(snow_ihash(i), snow_ihash(i + ivec2(1, 0)), u.x),
		mix(snow_ihash(i + ivec2(0, 1)), snow_ihash(i + ivec2(1, 1)), u.x),
		u.y
	);
}

// 0..1 ridge crest along the wind: long in the wind, tight across it.
float snow_ridge(vec2 xz, vec2 wind) {
	vec2 side = vec2(-wind.y, wind.x);
	vec2 q = vec2(dot(xz, wind) * 0.16, dot(xz, side) * 0.55);
	float n = snow_vnoise(q) * 0.7 + snow_vnoise(q * 2.0 + vec2(11.0, 5.0)) * 0.3;
	return smoothstep(0.45, 0.85, n);
}

// Settled depth at a world point from the shared globals and the city wind factor.
global uniform float snow_settled_depth;
global uniform float snow_drift_m;
global uniform vec2 snow_wind;
global uniform float snow_storm_share;

// Ridges only where the wind runs free: sheltered yards and drift banks lie smooth.
// SnowField.ridge_openness() mirrors this.
float snow_ridge_openness(float city) {
	return 1.0 - smoothstep(0.85, 1.35, city);
}

// Smooth settled depth, the part a 2 m grid can hold; both layers meet on it.
float snow_base_geom(float city) {
	return snow_settled_depth * city;
}

// Full settled depth with wind ridges, for shading and thin-snow tint.
float snow_base_depth(vec2 xz, float city) {
	return snow_base_geom(city) + snow_drift_m * min(city, 1.5) * snow_ridge_openness(city) * snow_ridge(xz, snow_wind);
}

// Thin snow lets the ground grey through; full cover reads white.
vec3 snow_thin_tint(vec3 snow, float depth) {
	return mix(snow * vec3(0.72, 0.72, 0.7), snow, smoothstep(0.03, 0.18, depth));
}

// Wind-polished crust on scoured ground reads greyer; fresh drift banks brighter.
vec3 snow_wind_tint(vec3 snow, float city) {
	vec3 crust = snow * vec3(0.84, 0.87, 0.92);
	vec3 c = mix(crust, snow, smoothstep(0.35, 0.95, city));
	return c * mix(1.0, 1.05, smoothstep(1.3, 1.9, city));
}

// Soft undirected ripple for sheltered snow, as a surface slope (shading only, so
// both snow layers match). Strongest where the wind cuts no ridges.
vec2 snow_ripple_slope(vec2 xz, float city) {
	float e = 0.05;
	vec2 p = xz * 0.9;
	float h = snow_vnoise(p) * 0.6 + snow_vnoise(p * 2.3 + vec2(3.0, 7.0)) * 0.4;
	float hx = snow_vnoise(p + vec2(e, 0.0)) * 0.6 + snow_vnoise((p + vec2(e, 0.0)) * 2.3 + vec2(3.0, 7.0)) * 0.4;
	float hz = snow_vnoise(p + vec2(0.0, e)) * 0.6 + snow_vnoise((p + vec2(0.0, e)) * 2.3 + vec2(3.0, 7.0)) * 0.4;
	float amp = 0.06 * mix(1.0, 0.35, snow_ridge_openness(city));
	return vec2(hx - h, hz - h) / e * 0.9 * amp;
}

// Shared world-space shading for SnowShell's outer rim and SnowChunkCover.
// Geometric snow-base slope is already in the displaced vertex positions;
// only ridge and ripple shading slopes are added to the terrain normal.
vec2 snow_outer_detail_slope(vec2 xz, float city) {
	const float e = 0.08;
	float hx = snow_base_depth(xz + vec2(e, 0.0), city) - snow_base_depth(xz - vec2(e, 0.0), city);
	float hz = snow_base_depth(xz + vec2(0.0, e), city) - snow_base_depth(xz - vec2(0.0, e), city);
	return vec2(hx, hz) / (2.0 * e) + snow_ripple_slope(xz, city);
}

vec3 snow_outer_normal(vec3 geometric_normal, vec2 xz, float city) {
	vec2 detail = snow_outer_detail_slope(xz, city);
	return normalize(normalize(geometric_normal) - vec3(detail.x, 0.0, detail.y));
}

vec3 snow_outer_albedo(vec3 fresh, vec3 world, float depth, float city) {
	vec3 color = fresh * (1.0 - snow_breakup(world, 5.0) * 0.03);
	color *= mix(1.0, 1.03, smoothstep(0.1, 0.4, depth));
	return snow_thin_tint(snow_wind_tint(color, city), depth);
}

// History remains logically persisted forever, but expensive geometric
// footprint relief is represented only near Henry. Beyond 25m it becomes
// streamed static snow. The fade follows WORLD distance to the continuously
// moving character rather than the 3.2m square recenter grid.
global uniform vec2 snow_player_xz;
float snow_trail_detail(vec2 world_xz) {
	return 1.0 - smoothstep(18.0, 25.0, distance(world_xz, snow_player_xz));
}

// Use the SAME deterministic world-space dither on both opaque meshes:
// exactly one of trail/chunk owns each transition pixel (no z fighting).
float snow_trail_dither(vec2 world_xz) {
	return snow_hash(floor(world_xz * 18.0));
}
