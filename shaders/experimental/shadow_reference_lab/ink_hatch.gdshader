shader_type spatial;
render_mode specular_disabled;

uniform vec3 paper_color = vec3(0.86, 0.88, 0.88);
uniform vec3 ink_color = vec3(0.17, 0.21, 0.23);
uniform vec3 wash_color = vec3(0.43, 0.47, 0.48);

varying vec3 world_pos;

float stripe(float v, float thickness) {
	float f = fract(v);
	float d = min(f, 1.0 - f);
	return 1.0 - smoothstep(thickness, thickness + 0.035, d);
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
	float density = 1.0 - shadow;
	float line_a = stripe((world_pos.x + world_pos.z * 0.78) * 2.35, 0.050);
	float line_b = stripe((world_pos.x - world_pos.z * 0.92) * 2.15 + 0.31, 0.045);
	float first = line_a * smoothstep(0.16, 0.38, density);
	float second = line_b * smoothstep(0.55, 0.78, density);
	float hatch = clamp(first * 0.68 + second * 0.74, 0.0, 1.0);
	float base_wash = smoothstep(0.08, 0.88, shadow);
	vec3 colour = mix(wash_color, paper_color, base_wash);
	colour = mix(colour, ink_color, hatch);
	DIFFUSE_LIGHT += colour * LIGHT_COLOR * ndl;
}
