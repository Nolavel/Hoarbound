// Diagnostic chart behind the ACTUAL 727 pane, not an invented game environment.
shader_type spatial;
render_mode unshaded, cull_disabled;
void fragment() {
	vec2 grid = floor(UV * vec2(12.0, 8.0));
	float checks = mod(grid.x + grid.y, 2.0);
	vec3 dark = vec3(0.13, 0.20, 0.25);
	vec3 light = vec3(0.36, 0.52, 0.56);
	ALBEDO = mix(dark, light, checks);
	ROUGHNESS = 1.0;
}
