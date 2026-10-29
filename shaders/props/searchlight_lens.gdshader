shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform sampler2D aura_mask : filter_linear_mipmap;
uniform sampler2D divine_mask : filter_linear_mipmap;
uniform vec4 lens_colour : source_color = vec4(1.0, 0.86, 0.58, 1.0);
uniform float lit = 0.0;
varying vec2 optic_uv;

void vertex() {
	optic_uv = VERTEX.xy / 0.158 + vec2(0.5);
}

void fragment() {
	float aura = texture(aura_mask, optic_uv).r;
	float divine = texture(divine_mask, optic_uv).r;
	float mask = mix(divine, aura, 0.18);
	ALBEDO = vec3(0.0);
	EMISSION = lens_colour.rgb * mask * lit * 3.0;
	ALPHA = mask * lit * 0.65;
}
