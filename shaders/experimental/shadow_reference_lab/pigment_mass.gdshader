shader_type spatial;
render_mode specular_disabled, ambient_light_disabled;

// Hoarbound reference-lab candidate: large pigment masses, pooled edge and sparse dry gaps.
// The cast-shadow lookup still decides WHERE shadow exists. The interior value structure is
// painted independently from penumbra width so the language does not depend on a wide PCF filter.
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

	// Tear the lookup itself with a single coarse, world-locked displacement. Unlike the old
	// three-octave production experiment this is intentionally one broad decision per ~2 m.
	float ox = noise2(world_pos.xz * 0.46 + vec2(7.3, 19.1)) * 2.0 - 1.0;
	float oz = noise2(world_pos.xz * 0.46 + vec2(-13.7, 5.9)) * 2.0 - 1.0;
	vec3 offset_world = vec3(ox, 0.0, oz) * 0.16;
	LIGHT_VERTEX = VERTEX + (VIEW_MATRIX * vec4(offset_world, 0.0)).xyz;
}

void light() {
	float ndl = max(dot(NORMAL, LIGHT), 0.0);
	float shadow = clamp(ATTENUATION, 0.0, 1.0);

	// These fields are deliberately coarse enough to read as painted masses rather than grain.
	float broad = fbm(world_pos.xz * 0.42 + vec2(3.7, 11.2));
	float secondary = noise2(world_pos.xz * 0.92 + vec2(21.7, 4.3));
	vec2 brush_dir = normalize(vec2(0.93, 0.37));
	float stroke = sin(dot(world_pos.xz, brush_dir) * 3.1 + broad * 3.8) * 0.5 + 0.5;
	float pigment = clamp(broad * 0.68 + secondary * 0.20 + stroke * 0.12, 0.0, 1.0);

	// Build the shadow body from large tonal islands even when ATTENUATION is already 0.
	// This is the important distinction from penumbra-only noise/three-tone experiments.
	float dark_mass = smoothstep(0.48, 0.64, pigment);
	float deep_mass = smoothstep(0.69, 0.82, pigment);
	vec3 painted_shadow = mix(wash_color, mass_color, dark_mass * 0.88);
	painted_shadow = mix(painted_shadow, core_color, deep_mass * 0.88);

	// Sparse dry openings: wide strokes lift pigment to a mid-value, never all the way to paper.
	float dry_field = secondary * 0.48 + stroke * 0.52;
	float dry_gap = smoothstep(0.78, 0.91, dry_field) * (1.0 - deep_mass * 0.72);
	painted_shadow = mix(painted_shadow, dry_color, dry_gap * 0.78);

	// Pigment pooling belongs to the physical boundary. Keep it narrow and dark so it reads as
	// capillary accumulation rather than another fuzzy shadow band.
	float rim = 1.0 - smoothstep(0.025, 0.115, abs(shadow - 0.53));
	float pool_variation = mix(0.55, 1.0, secondary);
	painted_shadow = mix(painted_shadow, pool_color, rim * pool_variation * 0.92);

	// The real shadow map only gates the painted body at its outer edge. A narrow transition is
	// enough; interior pigment structure no longer needs Soft High / a giant penumbra to exist.
	float lit = smoothstep(0.74, 0.98, shadow);
	vec3 colour = mix(painted_shadow, paper_color, lit);
	DIFFUSE_LIGHT += colour * LIGHT_COLOR * ndl * 0.74;
}
