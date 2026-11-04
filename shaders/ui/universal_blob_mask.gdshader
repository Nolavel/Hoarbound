shader_type canvas_item;

uniform vec4 blob_data[16];
uniform int blob_count = 0;
uniform float aspect_ratio = 1.0;
uniform float merge_width = 0.1;
uniform float edge_softness = 1.0;
uniform float stroke_width = 0.008;
uniform int display_mode = 1;
uniform bool invert_mask = false;
uniform bool use_content_texture = false;
uniform sampler2D content_texture : source_color, filter_linear;
uniform vec4 fill_color : source_color = vec4(1.0);
uniform vec4 outline_color : source_color = vec4(1.0);
uniform vec4 background_color : source_color = vec4(0.0);

#include "res://shaders/common/sdf_smooth_union.gdshaderinc"

void fragment() {
	vec2 scale = vec2(aspect_ratio, 1.0);
	vec2 p = (UV - vec2(0.5)) * scale;
	float distance_field = 100.0;

	for (int i = 0; i < 16; i++) {
		if (i >= blob_count) {
			break;
		}
		vec4 blob = blob_data[i];
		vec2 center = (blob.xy - vec2(0.5)) * scale;
		float circle = length(p - center) - max(blob.z, 0.00001);
		if (i == 0) {
			distance_field = circle;
		} else {
			distance_field = smooth_union(distance_field, circle, merge_width);
		}
	}

	float aa = max(fwidth(distance_field) * max(edge_softness, 0.1), 0.0005);
	float filled = 1.0 - smoothstep(-aa, aa, distance_field);
	float ring = 1.0 - smoothstep(
		max(stroke_width - aa, 0.0),
		stroke_width + aa,
		abs(distance_field)
	);
	float expanded = 1.0 - smoothstep(
		max(stroke_width - aa, 0.0),
		stroke_width + aa,
		distance_field
	);

	vec4 foreground = vec4(fill_color.rgb, fill_color.a * filled);
	if (display_mode == 1) {
		foreground = vec4(outline_color.rgb, outline_color.a * ring);
	} else if (display_mode == 2) {
		foreground.rgb = mix(outline_color.rgb, fill_color.rgb, filled);
		foreground.a = max(fill_color.a * filled, outline_color.a * expanded);
	} else if (display_mode == 3) {
		vec4 content = fill_color;
		if (use_content_texture) {
			content = texture(content_texture, UV);
		}
		float coverage = invert_mask ? (1.0 - filled) : filled;
		foreground = vec4(content.rgb, content.a * coverage);
	}

	if (display_mode == 3) {
		COLOR = foreground;
	} else {
		float opacity = foreground.a + background_color.a * (1.0 - foreground.a);
		vec3 rgb = (
			foreground.rgb * foreground.a
			+ background_color.rgb * background_color.a * (1.0 - foreground.a)
		) / max(opacity, 0.00001);
		COLOR = vec4(rgb, opacity);
	}
}
