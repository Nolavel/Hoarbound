shader_type spatial;
render_mode specular_disabled, ambient_light_disabled;

// Hoarbound reference-lab candidate: large pigment masses, a pooled dark rim and
// sparse dry gaps. World-space fields stay coarse on purpose; this is not a grain/noise pass.
uniform vec3 paper_color = vec3(0.82, 0.86, 0.88);
uniform vec3 wash_color = vec3(0.24, 0.34, 0.43);
uniform vec3 core_color = vec3(0.055, 0.09, 0.14);
uniform vec3 pool_color = vec3(0.025, 0.055, 0.09);
uniform vec3 mass_color = vec3(0.14, 0.23, 0.31);

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

	// Metre-scale structure: broad pooling field plus one authored brush direction.
	float broad = fbm(world_pos.xz * 0.24);
	float medium = noise2(world_pos.xz * 0.58 + vec2(21.7, 4.3));
	vec2 brush_dir = normalize(vec2(0.93, 0.37));
	float stroke = sin(dot(world_pos.xz, brush_dir) * 2.65 + broad * 4.2) * 0.5 + 0.5;

	// The physical shadow map still defines where shadow can exist. These fields only reshape
	// its value language into large painted decisions rather than fine procedural breakup.
	float warped = clamp(shadow + (broad - 0.5) * 0.30 + (stroke - 0.5) * 0.14, 0.0, 1.0);
	float wash = 1.0 - smoothstep(0.30, 0.90, warped);
	float core = 1.0 - smoothstep(0.10, 0.39, warped);

	// Pool pigment around the main wash boundary. The rim is irregular but coherent.
	float rim = 1.0 - smoothstep(0.025, 0.145, abs(warped - 0.48));
	float pooling = rim * mix(0.42, 1.0, medium);

	// A few broad darker masses survive inside the wash. These are deliberately sparse.
	float mass_field = broad * 0.68 + medium * 0.32;
	float mass = smoothstep(0.58, 0.76, mass_field)
		* smoothstep(0.08, 0.25, warped)
		* (1.0 - smoothstep(0.70, 0.91, warped));

	// Dry-brush holes belong only to the mid wash, never to the core or clean snow.
	float dry_field = medium * 0.56 + stroke * 0.44;
	float dry_gap = smoothstep(0.76, 0.91, dry_field)
		* smoothstep(0.34, 0.54, warped)
		* (1.0 - smoothstep(0.72, 0.88, warped));

	vec3 colour = mix(paper_color, wash_color, wash);
	colour = mix(colour, core_color, core);
	colour = mix(colour, pool_color, pooling * 0.84);
	colour = mix(colour, mass_color, mass * 0.78);
	colour = mix(colour, paper_color, dry_gap * 0.82);

	// Keep the filmic reference rig from washing the values back toward white.
	DIFFUSE_LIGHT += colour * LIGHT_COLOR * ndl * 0.70;
}
