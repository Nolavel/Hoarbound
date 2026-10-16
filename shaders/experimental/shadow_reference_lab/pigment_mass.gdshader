shader_type spatial;
render_mode specular_disabled, ambient_light_disabled;

// Hoarbound reference-lab candidate: large pigment masses, pooled edge and sparse dry gaps.
// The physical cast-shadow lookup decides WHERE shadow exists. Interior value structure is
// painted independently from penumbra width; silhouette tearing is deliberately excluded here
// so this lab measures the pigment language alone.
uniform vec3 paper_color = vec3(0.88, 0.90, 0.91);
uniform vec3 wash_color = vec3(0.30, 0.39, 0.47);
uniform vec3 mass_color = vec3(0.16, 0.25, 0.33);
uniform vec3 core_color = vec3(0.055, 0.085, 0.13);
uniform vec3 pool_color = vec3(0.018, 0.045, 0.075);
uniform vec3 dry_color = vec3(0.48, 0.56, 0.61);

varying vec3 world_pos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.58;
	for (int i = 0; i < 3; i++) {
		v += noise2(p) * a;
		p = p * 2.03 + vec2(13.1, 7.7);
		a *= 0.44;
	}
	return v / 0.949;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = paper_color;
	ROUGHNESS = 1.0;
}

void light() {
	float ndl = max(dot(NORMAL, LIGHT), 0.0);
	float shadow = clamp(ATTENUATION, 0.0, 1.0);

	// Coarse world-space fields: roughly 1-3 m decisions, not high-frequency material noise.
	float broad = fbm(world_pos.xz * 0.42 + vec2(3.7, 11.2));
	float secondary = noise2(world_pos.xz * 0.92 + vec2(21.7, 4.3));
	vec2 brush_dir = normalize(vec2(0.93, 0.37));
	float stroke = sin(dot(world_pos.xz, brush_dir) * 3.1 + broad * 3.8) * 0.5 + 0.5;
	float pigment = clamp(broad * 0.68 + secondary * 0.20 + stroke * 0.12, 0.0, 1.0);

	// The entire binary/core part of the physical shadow now carries large tonal islands.
	// No dependency on a broad soft-filter penumbra is required for these masses to exist.
	float dark_mass = smoothstep(0.46, 0.61, pigment);
	float deep_mass = smoothstep(0.66, 0.79, pigment);
	vec3 painted_shadow = mix(wash_color, mass_color, dark_mass * 0.90);
	painted_shadow = mix(painted_shadow, core_color, deep_mass * 0.86);

	// Sparse directional dry openings lift the wash only to a mid-value. They cannot punch
	// through to white paper, which keeps the cast shadow coherent as one large shape.
	float dry_field = secondary * 0.42 + stroke * 0.58;
	float dry_gap = smoothstep(0.80, 0.92, dry_field) * (1.0 - deep_mass * 0.76);
	painted_shadow = mix(painted_shadow, dry_color, dry_gap * 0.72);

	// Narrow physical-boundary pooling. This is deliberately a small accent, not the main effect.
	float rim = 1.0 - smoothstep(0.025, 0.115, abs(shadow - 0.53));
	float pool_variation = mix(0.58, 1.0, secondary);
	painted_shadow = mix(painted_shadow, pool_color, rim * pool_variation * 0.90);

	// ATTENUATION is only the outer membership/transition mask here. The interior colour above
	// remains visible even when the physical shadow has already saturated to its core value.
	float lit = smoothstep(0.72, 0.96, shadow);
	vec3 colour = mix(painted_shadow, paper_color, lit);
	DIFFUSE_LIGHT += colour * LIGHT_COLOR * ndl * 0.74;
}
