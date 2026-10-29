shader_type spatial;
render_mode specular_disabled, ambient_light_disabled;

uniform vec3 paper_color = vec3(0.89, 0.91, 0.92);
uniform vec3 shadow_color = vec3(0.12, 0.18, 0.23);

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
	float n = noise2(world_pos.xz * 0.85);
	float wave = sin((world_pos.x * 1.25 + world_pos.z * 0.72) * 3.0 + n * 3.2) * 0.5 + 0.5;
	float threshold = 0.50 + (n - 0.5) * 0.28 + (wave - 0.5) * 0.14;
	float toon = smoothstep(threshold - 0.04, threshold + 0.04, shadow);
	vec3 painted = mix(shadow_color, paper_color, toon);
	DIFFUSE_LIGHT += painted * LIGHT_COLOR * ndl;
}
