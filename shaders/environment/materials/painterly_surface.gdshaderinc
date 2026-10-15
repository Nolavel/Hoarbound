// Surface-bound pigment breakup for static architecture and ground.
// This is deliberately separate from the camera-space paper/distance wash.
// One broad mask plus one anisotropic mask keep the cost bounded and world-stable.

global uniform float painterly_surface_strength;
global uniform float painterly_surface_pigment_strength;
global uniform float painterly_surface_brush_strength;
global uniform sampler2D painterly_surface_brush_mask : filter_linear_mipmap, repeat_enable;

uniform float painterly_pigment_scale_m : hint_range(2.0, 20.0) = 7.5;
uniform vec2 painterly_brush_direction = vec2(0.32, 0.95);
uniform float painterly_brush_length_m : hint_range(1.0, 12.0) = 5.5;
uniform float painterly_brush_width_m : hint_range(0.2, 3.0) = 0.65;


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


// Large pigment masses and long broken strokes are sampled in the dominant
// surface plane. Buildings therefore read vertically; ground follows XZ.
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

	vec2 mass_uv = plane / max(painterly_pigment_scale_m, 0.1);
	mass_uv += vec2(0.17, 0.31) * plane_seed;
	float mass = smoothstep(0.28, 0.72, texture(painterly_surface_brush_mask, mass_uv).r);

	vec2 direction = painterly_brush_direction / max(length(painterly_brush_direction), 1e-4);
	vec2 across = vec2(-direction.y, direction.x);
	vec2 stroke_uv = vec2(
		dot(plane, direction) / max(painterly_brush_length_m, 0.1),
		dot(plane, across) / max(painterly_brush_width_m, 0.05)
	);
	stroke_uv += vec2(0.37, 0.61) * plane_seed;
	float stroke = smoothstep(0.32, 0.68, texture(painterly_surface_brush_mask, stroke_uv).r);

	float pigment = clamp(painterly_surface_pigment_strength, 0.0, 0.35);
	float brush = clamp(painterly_surface_brush_strength, 0.0, 0.2);
	float mass_delta = (mass - 0.28) * pigment;
	float stroke_delta = (stroke - 0.5) * 2.0 * brush * (0.35 + 0.65 * mass);
	float value_factor = clamp(1.0 - strength * (mass_delta + stroke_delta), 0.72, 1.08);

	// Pooling stays neutral-cool; it must not invent warm windows or a new paper layer.
	float pool = clamp(strength * mass * pigment * 0.35, 0.0, 0.08);
	vec3 value_shaped = base_color * value_factor;
	return mix(value_shaped, value_shaped * vec3(0.92, 0.96, 1.0), pool);
}
