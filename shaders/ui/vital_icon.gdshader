shader_type canvas_item;

// Vital symbol: half-tone while the value is safe, full colour tinted by state as it nears critical.

uniform float vivid : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(1.0);

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	vec3 col = mix(vec3(g) * 0.9, mix(c.rgb, tint.rgb, 0.35), vivid);
	COLOR = vec4(col, c.a * mix(0.4, 1.0, vivid) * COLOR.a);
}
