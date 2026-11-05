shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled;
// Full-screen blur of everything but the held pack and the inventory (they write STENCIL 9; PackFocusBlur).
stencil_mode read, compare_not_equal, 9;

uniform sampler2D screen: hint_screen_texture, filter_linear_mipmap;
// Mip level sampled, the disc's radius in that level's pixels, and the fade (0 sharp, 1 fully blurred).
uniform float lod = 2.5;
uniform float radius = 2.2;
uniform float strength: hint_range(0.0, 1.0) = 1.0;

const vec2 DISC[12] = vec2[](
	vec2(-0.326, -0.406), vec2(-0.840, -0.074), vec2(-0.696, 0.457), vec2(-0.203, 0.621),
	vec2(0.962, -0.195), vec2(0.473, -0.480), vec2(0.519, 0.767), vec2(0.185, -0.893),
	vec2(0.507, 0.064), vec2(0.896, 0.412), vec2(-0.322, -0.933), vec2(-0.792, -0.598)
);

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 step = radius * exp2(lod) / VIEWPORT_SIZE;
	vec3 sum = textureLod(screen, SCREEN_UV, lod).rgb;
	for (int i = 0; i < 12; i++) {
		sum += textureLod(screen, SCREEN_UV + DISC[i] * step, lod).rgb;
	}
	ALBEDO = sum / 13.0;
	ALPHA = strength;
}
