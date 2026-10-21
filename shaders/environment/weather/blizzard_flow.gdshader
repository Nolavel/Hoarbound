// Blown snow in a blizzard flow volume (scripts/vfx/blizzard_flow.gd): extinction from the wind,
// densest near the street and thinning with height, its shape advected downwind and fading at the box.
shader_type fog;

uniform float density = 0.0;
uniform vec3 wind = vec3(0.0);
uniform float scale_height = 1.6;
uniform sampler3D flow_noise : repeat_enable;
uniform vec3 snow_albedo : source_color = vec3(0.93, 0.95, 0.98);

void fog() {
	// Height above the street: the box sits with its base just under the pavement.
	float h = UVW.y * SIZE.y;
	float profile = exp(-h / max(scale_height, 0.1));
	// Two octaves carried by the wind at different speeds: the body rolls and tears as it moves.
	vec3 p = WORLD_POSITION;
	float body = texture(flow_noise, (p - wind * TIME * 0.9) * vec3(0.018, 0.05, 0.018)).r;
	float tear = texture(flow_noise, (p - wind * TIME * 1.4) * vec3(0.05, 0.11, 0.05) + vec3(0.37)).r;
	float shape = smoothstep(0.35, 0.75, body * 0.7 + tear * 0.45);
	// Soft ends along the street, soft kerbs across it, nothing at the lid.
	vec3 edge = min(UVW, 1.0 - UVW);
	float fade = smoothstep(0.0, 0.18, edge.x) * smoothstep(0.0, 0.3, edge.z) * smoothstep(0.0, 0.35, 1.0 - UVW.y);
	DENSITY = density * profile * shape * fade;
	ALBEDO = snow_albedo;
}
