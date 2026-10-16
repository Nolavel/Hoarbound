shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_test_disabled, depth_draw_never;

// Dual 3D LUT blend for ColorGradeController transitions.
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler3D lut_from : source_color, filter_linear, repeat_disable;
uniform sampler3D lut_to : source_color, filter_linear, repeat_disable;
uniform float blend_weight : hint_range(0.0, 1.0, 0.001) = 1.0;
uniform float brightness_from : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float brightness_to : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float contrast_from : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float contrast_to : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float saturation_from : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float saturation_to : hint_range(0.0, 2.0, 0.01) = 1.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

vec3 apply_bcs(vec3 color, float brightness, float contrast, float saturation) {
	color *= brightness;
	color = mix(vec3(0.5), color, contrast);
	float luma = dot(color, vec3(0.333333));
	color = mix(vec3(luma), color, saturation);
	return color;
}

vec3 sample_lut(sampler3D lut, vec3 color) {
	vec3 uvw = clamp(color, vec3(0.0), vec3(1.0));
	return texture(lut, uvw).rgb;
}

void fragment() {
	vec3 src = texture(screen_texture, SCREEN_UV).rgb;
	float w = clamp(blend_weight, 0.0, 1.0);
	vec3 graded_from = apply_bcs(sample_lut(lut_from, src), brightness_from, contrast_from, saturation_from);
	vec3 graded_to = apply_bcs(sample_lut(lut_to, src), brightness_to, contrast_to, saturation_to);
	ALBEDO = mix(graded_from, graded_to, w);
	ALPHA = 1.0;
}
