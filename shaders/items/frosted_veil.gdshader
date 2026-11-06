shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// Frosted glass over a container's open face (owner: what is inside reads as unclear shapes until searched):
// what lies behind, sampled from the screen at a blurred mip, slightly lifted toward a cold haze.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float blur_lod : hint_range(0.0, 8.0) = 2.6;
uniform vec4 haze : source_color = vec4(0.62, 0.66, 0.72, 1.0);
uniform float haze_amount : hint_range(0.0, 1.0) = 0.05;
uniform float strength : hint_range(0.0, 1.0) = 0.8;

void fragment() {
	vec3 behind = textureLod(screen_texture, SCREEN_UV, blur_lod).rgb;
	ALBEDO = mix(behind, haze.rgb, haze_amount);
	ALPHA = strength;
}
