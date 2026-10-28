// Fire-gutted facade for building conditions (#235): charcoal walls, darker towards the
// top where smoke rolled out, with vertical soot streaks. World-space, no UVs needed.
shader_type spatial;

uniform vec4 char_color : source_color = vec4(0.09, 0.08, 0.075, 1.0);
uniform vec4 ash_color : source_color = vec4(0.30, 0.28, 0.26, 1.0);
// Height of the wall above its base, metres; soot thickens towards it.
uniform float wall_height = 4.0;
uniform float base_y = 0.0;

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float h = clamp((world_pos.y - base_y) / max(wall_height, 0.5), 0.0, 1.0);
	float along = world_pos.x + world_pos.z;
	// Streaks: narrow along the wall, long up it.
	float streak = noise(vec2(along * 3.0, world_pos.y * 0.35));
	float ash = smoothstep(0.55, 0.85, noise(vec2(along * 0.8, world_pos.y * 0.8))) * (1.0 - h);
	vec3 colour = mix(char_color.rgb, ash_color.rgb, ash * 0.6);
	colour *= mix(1.0, 0.45, h * smoothstep(0.3, 0.8, streak));
	ALBEDO = colour;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}

