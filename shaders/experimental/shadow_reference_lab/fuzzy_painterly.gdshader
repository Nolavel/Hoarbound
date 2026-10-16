shader_type spatial;
render_mode specular_disabled;

uniform vec3 paper_color = vec3(0.84, 0.87, 0.88);
uniform vec3 shadow_color = vec3(0.27, 0.33, 0.37);

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
	float a = 0.55;
	for (int i = 0; i < 3; i++) {
		v += noise2(p) * a;
		p = p * 2.03 + vec2(17.3, 9.1);
		a *= 0.48;
	}
	return v / 0.952;
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
	float broad = fbm(world_pos.xz * 0.52);
	vec2 stroke_dir = normalize(vec2(0.94, 0.34));
	float stroke = sin(dot(world_pos.xz, stroke_dir) * 5.4 + broad * 4.1) * 0.5 + 0.5;
	float edge_band = 1.0 - smoothstep(0.10, 0.36, abs(shadow - 0.5));
	float shifted = clamp(shadow + (broad - 0.5) * 0.34 * edge_band + (stroke - 0.5) * 0.17 * edge_band, 0.0, 1.0);
	float painted = smoothstep(0.19, 0.82, shifted);
	float dry_gap = smoothstep(0.73, 0.91, broad * 0.67 + stroke * 0.33) * edge_band;
	painted = max(painted, dry_gap * 0.82);
	vec3 colour = mix(shadow_color, paper_color, painted);
	DIFFUSE_LIGHT += colour * LIGHT_COLOR * ndl;
}
