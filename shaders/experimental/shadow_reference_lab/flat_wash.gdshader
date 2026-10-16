shader_type spatial;
render_mode specular_disabled;

uniform vec3 paper_color = vec3(0.84, 0.87, 0.88);
uniform vec3 shadow_color = vec3(0.28, 0.34, 0.38);

void fragment() {
	ALBEDO = paper_color;
	ROUGHNESS = 1.0;
}

void light() {
	float ndl = max(dot(NORMAL, LIGHT), 0.0);
	float shadow = clamp(ATTENUATION, 0.0, 1.0);
	float wash = smoothstep(0.08, 0.92, shadow);
	vec3 painted = mix(shadow_color, paper_color, wash);
	DIFFUSE_LIGHT += painted * LIGHT_COLOR * ndl;
}
