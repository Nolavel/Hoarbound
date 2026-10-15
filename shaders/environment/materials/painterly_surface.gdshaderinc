// Surface-bound pigment breakup for static architecture and ground.
// This is deliberately separate from the camera-space paper/distance wash.
// Two low-frequency value-noise evaluations keep the result world-stable and bounded.

global uniform float painterly_surface_strength;
global uniform float painterly_surface_pigment_strength;
global uniform float painterly_surface_brush_strength;

uniform float painterly_pigment_scale_m : hint_range(2.0, 20.0) = 9.0;
uniform vec2 painterly_brush_direction = vec2(0.32, 0.95);
uniform float painterly_brush_length_m : hint_range(1.0, 16.0) = 7.0;
uniform float painterly_brush_width_m : hint_range(0.2, 3.0) = 0.85;


float hfn_painterly_surface_hash(ivec2 cell) {
	uint h = uint(cell.x) * 374761393u + uint(cell.y) * 668265263u;
	h = (h ^ (h >> 13u)) * 1274126177u;
	h ^= h >> 16u;
	return float(h & 65535u) / 65535.0;
}


float hfn_painterly_surface_noise(vec2 p) {
	vec2 base = floor(p);
	ivec2 cell = ivec2(base);
	vec2 f = p - base;
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(
			hfn_painterly_surface_hash(cell),
			hfn_painterly_surface_hash(cell + ivec2(1, 0)),
			u.x
		),
		mix(
			hfn_painterly_surface_hash(cell + ivec2(0, 1)),
			hfn_painterly_surface_hash(cell + ivec2(1, 1)),
			u.x
		),
		u.y
	);
}


vec2 hfn_painterly_surface_plane(vec3 world_pos, vec3 world_normal) {
	vec3 n = abs(world_normal / max(length(world_normal), 1e-5));
	if (n.y >= n.x && n.y >= n.z) {
		return world_pos.xz;
	}
	if (n.x >= n.z) {
		return vec2(world_pos.z, world_pos.y);
	}
	return vec2(world_pos.x, world_pos.y);
}


// Broad pigment and long broken strokes share the dominant surface plane.
// On walls the second coordinate is height, so the default flow rises vertically;
// on ground the same vector becomes a diagonal sweep across world XZ.
vec3 hfn_painterly_surface_color(
	vec3 base_color,
	vec3 world_pos,
	vec3 world_normal,
	float surface_weight
) {
	float strength = clamp(painterly_surface_strength, 0.0, 1.0) * clamp(surface_weight, 0.0, 1.0);
	if (strength <= 0.0) {
		return base_color;
	}

	vec3 n = world_normal / max(length(world_normal), 1e-5);
	vec2 plane = hfn_painterly_surface_plane(world_pos, n);
	float plane_seed = dot(abs(n), vec3(13.1, 29.7, 47.3));

	// Rotate the metre-space domain so the broad cells never align to walls or chunk axes.
	vec2 rotated = vec2(
		plane.x * 0.8 - plane.y * 0.6,
		plane.x * 0.6 + plane.y * 0.8
	);
	vec2 mass_uv = rotated / max(painterly_pigment_scale_m, 0.1);
	mass_uv += vec2(0.17, 0.31) * plane_seed;
	float mass = smoothstep(0.20, 0.80, hfn_painterly_surface_noise(mass_uv));

	vec2 direction = painterly_brush_direction / max(length(painterly_brush_direction), 1e-4);
	vec2 across = vec2(-direction.y, direction.x);
	vec2 stroke_uv = vec2(
		dot(plane, direction) / max(painterly_brush_length_m, 0.1),
		dot(plane, across) / max(painterly_brush_width_m, 0.05)
	);
	stroke_uv += vec2(0.37, 0.61) * plane_seed;
	float stroke = smoothstep(0.24, 0.76, hfn_painterly_surface_noise(stroke_uv));

	float pigment = clamp(painterly_surface_pigment_strength, 0.0, 0.35);
	float brush = clamp(painterly_surface_brush_strength, 0.0, 0.2);
	float mass_delta = (mass - 0.30) * pigment;
	float stroke_delta = (stroke - 0.5) * 2.0 * brush * (0.30 + 0.70 * mass);
	float value_factor = clamp(1.0 - strength * (mass_delta + stroke_delta), 0.74, 1.07);

	// Pooling stays neutral-cool; it must not invent warm windows or a new paper layer.
	float pool = clamp(strength * mass * pigment * 0.28, 0.0, 0.07);
	vec3 value_shaped = base_color * value_factor;
	return mix(value_shaped, value_shaped * vec3(0.93, 0.965, 1.0), pool);
}
