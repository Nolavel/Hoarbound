// Blown snow in a blizzard flow volume (scripts/vfx/blizzard_flow.gd): extinction from the wind,
// densest near the street and thinning with height, its shape advected downwind and fading at the box.
shader_type fog;

uniform float density = 0.0;
uniform vec3 wind = vec3(0.0);
uniform float scale_height = 1.6;
uniform sampler3D flow_noise : repeat_enable;
uniform vec3 snow_albedo : source_color = vec3(0.97, 0.98, 1.0);
uniform float glow = 0.06;

void fog() {
	// Height above the street: the box sits with its base just under the pavement.
	float h = UVW.y * SIZE.y;
	float profile = exp(-h / max(scale_height, 0.1));
	// Billows ~12 m long with gaps between them, torn at ~5 m: two octaves carried by the wind at
	// different speeds, so the cloud rolls, splits and re-forms as it travels.
	vec3 p = WORLD_POSITION;
	float body = texture(flow_noise, (p - wind * TIME * 0.95) * vec3(0.025, 0.05, 0.025)).r;
	float tear = texture(flow_noise, (p - wind * TIME * 1.3) * vec3(0.06, 0.12, 0.06) + vec3(0.37)).r;
	float shape = smoothstep(0.45, 0.72, body * 0.75 + tear * 0.35);
	// Soft ends along the street, soft kerbs across it, nothing at the lid.
	vec3 edge = min(UVW, 1.0 - UVW);
	float fade = smoothstep(0.0, 0.18, edge.x) * smoothstep(0.0, 0.3, edge.z) * smoothstep(0.0, 0.35, 1.0 - UVW.y);
	// About 40 % of the box is cloud: the cores carry the box's mean extinction.
	DENSITY = density * 2.5 * profile * shape * fade;
	ALBEDO = snow_albedo;
	// Blown snow forward-scatters the overcast: the billows read lighter than the fog behind them.
	EMISSION = snow_albedo * glow * shape * profile;
}
