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

// Value noise with its gradient: (value, d/dx, d/dy), one lookup for shading slopes.
vec3 snow_vnoise_d(vec2 p) {
	vec2 fl = floor(p);
	ivec2 i = ivec2(fl);
	vec2 f = p - fl;
	vec2 u = f * f * (3.0 - 2.0 * f);
	vec2 du = 6.0 * f * (1.0 - f);
	float a = snow_ihash(i);
	float b = snow_ihash(i + ivec2(1, 0));
	float c = snow_ihash(i + ivec2(0, 1));
	float d = snow_ihash(i + ivec2(1, 1));
	float k = a - b - c + d;
	return vec3(a + (b - a) * u.x + (c - a) * u.y + k * u.x * u.y,
		du * vec2(b - a + k * u.y, c - a + k * u.x));
}

// Derivative of smoothstep(e0, e1, x) with respect to x.
float snow_smoothstep_d(float e0, float e1, float x) {
	float t = clamp((x - e0) / (e1 - e0), 0.0, 1.0);
	return 6.0 * t * (1.0 - t) / (e1 - e0);
}

// Wind-cut drift ridge with its xz gradient, (crest 0..1, d/dx, d/dz): a gentle rise
// into the wind and a steep lee drop every ~6 m, crests wandering and broken into
// segments (sastrugi). SnowField.ridge_at() mirrors the crest.
vec3 snow_ridge_d(vec2 xz, vec2 wind) {
	vec2 side = vec2(-wind.y, wind.x);
	float along = dot(xz, wind);
	float across = dot(xz, side);
	vec3 n1 = snow_vnoise_d(vec2(along * 0.05, across * 0.2));
	float s = fract(along * 0.16 + n1.x * 2.5);
	vec2 ds = 0.16 * wind + 2.5 * (n1.y * 0.05 * wind + n1.z * 0.2 * side);
	float rise = smoothstep(0.0, 0.8, s);
	float drop = 1.0 - smoothstep(0.8, 1.0, s);
	float d_profile = snow_smoothstep_d(0.0, 0.8, s) * drop - rise * snow_smoothstep_d(0.8, 1.0, s);
	vec3 n2 = snow_vnoise_d(vec2(along * 0.12, across * 0.45) + vec2(11.0, 5.0));
	float segment = smoothstep(0.35, 0.75, n2.x);
	vec2 d_segment = snow_smoothstep_d(0.35, 0.75, n2.x) * (n2.y * 0.12 * wind + n2.z * 0.45 * side);
	return vec3(rise * drop * segment, d_profile * ds * segment + rise * drop * d_segment);
}

float snow_ridge(vec2 xz, vec2 wind) {
	return snow_ridge_d(xz, wind).x;
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

// Smooth settled depth before the wind's ridges.
float snow_base_geom(float city) {
	return snow_settled_depth * city;
}

// How much ridge the wind cuts where the city factor is `city`.
float snow_ridge_amount(float city) {
	return snow_drift_m * min(city, 1.5) * snow_ridge_openness(city);
}

// Full settled depth with wind ridges, for shading and thin-snow tint.
float snow_base_depth(vec2 xz, float city) {
	return snow_base_geom(city) + snow_ridge_amount(city) * snow_ridge(xz, snow_wind);
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

// Fine surface relief as a slope (shading only, so both snow layers match): small
// sastrugi aligned with the wind where it runs free, soft ripple in sheltered snow.
vec2 snow_ripple_slope(vec2 xz, float city) {
	float open = snow_ridge_openness(city);
	vec2 slope = vec2(0.0);
	if (open < 0.99) {
		vec2 p = xz * 0.9;
		vec2 g = snow_vnoise_d(p).yz * 0.6 + snow_vnoise_d(p * 2.3 + vec2(3.0, 7.0)).yz * 0.4 * 2.3;
		slope += g * 0.9 * 0.06 * (1.0 - open);
	}
	if (open > 0.01) {
		// Small sastrugi: ~0.7 m apart along the wind, each with a steep lee face.
		slope += snow_ridge_d(xz * 9.0, snow_wind).yz * 9.0 * 0.012 * open;
	}
	return slope;
}

// Grain a few centimetres across, as a slope: snow is clumped crystals, not a gel.
// Each octave fades before a pixel spans it, so the far cover does not shimmer.
vec2 snow_grain_slope(vec2 xz, float footprint) {
	vec2 g = vec2(0.0);
	float coarse = 1.0 - smoothstep(0.015, 0.05, footprint);
	if (coarse > 0.0) {
		g += snow_vnoise_d(xz * 14.0).yz * (14.0 * 0.0045 * coarse);
		float fine = 1.0 - smoothstep(0.005, 0.016, footprint);
		if (fine > 0.0) {
			g += snow_vnoise_d(xz * 41.0 + vec2(5.3, 1.7)).yz * (41.0 * 0.0013 * fine);
		}
	}
	return g;
}

// Brightness of wind-packed patches a metre or two across.
float snow_patch_albedo(vec2 xz) {
	return 1.0 + (snow_vnoise_d(xz * 0.6 + vec2(3.1, 9.2)).x - 0.5) * 0.08;
}

// Grain brightness: hollows see less sky, which keeps relief in shadowed snow.
float snow_grain_albedo(vec2 xz, float footprint) {
	float v = 0.0;
	float mid = 1.0 - smoothstep(0.03, 0.09, footprint);
	if (mid > 0.0) {
		v -= (1.0 - snow_vnoise_d(xz * 14.0).x) * 0.07 * mid;
		float fine = 1.0 - smoothstep(0.008, 0.025, footprint);
		if (fine > 0.0) {
			v += (snow_vnoise_d(xz * 33.0 + vec2(1.3, 7.9)).x - 0.5) * 0.06 * fine;
		}
	}
	return 1.0 + v;
}

// Grain on the final, up-facing surface; it fades on cut walls, where a pattern in xz
// would stretch into vertical streaks. `amount` 0..1 (packed floors are smoother).
void snow_apply_grain(inout vec3 n, inout vec3 albedo, vec2 xz, float footprint, float amount) {
	float up = smoothstep(0.88, 0.97, n.y) * amount;
	if (up <= 0.0) {
		return;
	}
	vec2 g = snow_grain_slope(xz, footprint) * up;
	n = normalize(n - vec3(g.x, 0.0, g.y));
	albedo *= mix(1.0, snow_grain_albedo(xz, footprint), up);
}

// Ice facets that flash toward the sun: a few per square decimetre, each a tilted
// mirror in a 2 cm cell. xyz the facet normal (world), w its weight 0..1.
vec4 snow_glint_facet(vec2 xz, vec3 n, float footprint) {
	vec2 p = xz * 45.0;
	ivec2 c = ivec2(floor(p));
	float on = step(0.85, snow_ihash(c)) * (1.0 - smoothstep(0.012, 0.035, footprint));
	if (on <= 0.0) {
		return vec4(n, 0.0);
	}
	vec2 centre = vec2(snow_ihash(c + ivec2(17, 3)), snow_ihash(c + ivec2(5, 29))) * 0.6 + 0.2;
	float disc = 1.0 - smoothstep(0.1, 0.2, length(fract(p) - centre));
	vec3 tilt = vec3(snow_ihash(c + ivec2(41, 7)) - 0.5, 0.0, snow_ihash(c + ivec2(13, 53)) - 0.5) * 1.6;
	return vec4(normalize(n + tilt), on * disc);
}

// The facet's flash under one light (view-space vectors), to add to SPECULAR_LIGHT.
float snow_glint_light(vec3 facet, float weight, vec3 light, vec3 view) {
	float lit = dot(facet, light);
	if (weight <= 0.0 || lit <= 0.0) {
		return 0.0;
	}
	vec3 h = light + view;
	return pow(max(dot(facet, h * inversesqrt(max(dot(h, h), 1e-6))), 0.0), 220.0) * weight * 7.0 * min(lit * 10.0, 1.0);
}

// Henry's snow LOD: xy his position, z the Chebyshev radius inside which the
// clipmap (snow_ground) draws and outside which the chunk cover does, w 1 when live.
global uniform vec4 snow_lod;
// Both draw this far across the handoff; there they are the same surface.
const float SNOW_LOD_OVERLAP_M = 0.15;

float snow_lod_distance(vec2 xz) {
	vec2 d = abs(xz - snow_lod.xy);
	return max(d.x, d.y);
}

// Capture-only: the drawn height as emission, 4 m / 25 cm / 16 mm periods in RGB.
// The sRGB encode is undone so an 8-bit readback stores each period linearly.
vec3 snow_debug_height(float y) {
	vec3 v = vec3(fract(y / 4.0), fract(y / 0.25), fract(y / 0.016));
	return mix(v / 12.92, pow((v + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), v));
}
