shader_type spatial;
render_mode specular_disabled;

uniform vec3 paper_color = vec3(0.85, 0.88, 0.89);
uniform vec3 wash_color = vec3(0.30, 0.37, 0.42);
uniform vec3 pool_color = vec3(0.19, 0.25, 0.30);

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
		p = p * 2.07 + vec2(11.7, 23.4);
		a *= 0.46;
	}
	return v / 0.968;
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
	float coarse = fbm(world_pos.xz * 0.30);
	float fine = noise2(world_pos.xz * 1.55 + vec2(5.2, 17.9));
	float warped = clamp(shadow + (coarse - 0.5) * 0.20, 0.0, 1.0);
	float wash = smoothstep(0.10, 0.88, warped);
	float edge = 1.0 - smoothstep(0.035, 0.18, abs(warped - 0.50));
	float pooling = edge * (0.58 + 0.42 * fine);
	vec3 colour = mix(wash_color, paper_color, wash);
	colour = mix(colour, pool_color, pooling * 0.58);
	DIFFUSE_LIGHT += colour * LIGHT_COLOR * ndl;
}
