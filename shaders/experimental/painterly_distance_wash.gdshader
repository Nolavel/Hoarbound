shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_test_disabled, depth_draw_never;

// Experimental Hoarbound painterly distance wash.
// Reference target: depth removes information in three readable stages.
// Near silhouettes stay crisp; mid-distance facades collapse into broader value
// masses; far architecture becomes pale cold paper/snow mass. This is not DOF.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;

uniform float mid_start_m : hint_range(0.0, 100.0, 0.5) = 12.0;
uniform float mid_full_m : hint_range(5.0, 150.0, 0.5) = 35.0;
uniform float far_start_m : hint_range(10.0, 200.0, 1.0) = 35.0;
uniform float far_full_m : hint_range(20.0, 300.0, 1.0) = 90.0;
uniform vec4 wash_color : source_color = vec4(0.92, 0.94, 0.95, 1.0);

uniform float mid_desaturation : hint_range(0.0, 1.0, 0.01) = 0.52;
uniform float far_desaturation : hint_range(0.0, 1.0, 0.01) = 0.26;
uniform float mid_contrast_compression : hint_range(0.0, 1.0, 0.01) = 0.38;
uniform float far_contrast_compression : hint_range(0.0, 1.0, 0.01) = 0.28;
uniform float mid_dark_value_lift : hint_range(0.0, 1.0, 0.01) = 0.28;
uniform float far_dark_value_lift : hint_range(0.0, 1.0, 0.01) = 0.26;
uniform float mid_paper_mix : hint_range(0.0, 1.0, 0.01) = 0.34;
uniform float far_paper_mix : hint_range(0.0, 1.0, 0.01) = 0.48;

uniform float blur_start_m : hint_range(0.0, 150.0, 1.0) = 28.0;
uniform float blur_end_m : hint_range(10.0, 250.0, 1.0) = 90.0;
uniform float blur_strength : hint_range(0.0, 1.0, 0.01) = 0.24;
uniform float blur_radius_px : hint_range(0.0, 6.0, 0.1) = 2.6;
uniform float silhouette_guard_m : hint_range(0.5, 30.0, 0.5) = 6.0;
uniform vec2 viewport_size = vec2(1280.0, 720.0);

uniform float horizon_band : hint_range(0.01, 0.5, 0.01) = 0.16;
uniform float horizon_paper_boost : hint_range(0.0, 0.5, 0.01) = 0.10;


void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}


vec3 view_position_at(vec2 uv) {
	float raw_depth = textureLod(depth_texture, uv, 0.0).r;
	vec3 ndc = vec3(uv * 2.0 - 1.0, raw_depth);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float safe_w = abs(view.w) > 0.000001 ? view.w : 1.0;
	return view.xyz / safe_w;
}


float distance_at(vec2 uv) {
	float raw_depth = textureLod(depth_texture, uv, 0.0).r;
	if (raw_depth >= 0.999999) {
		return far_full_m * 2.0;
	}
	return length(view_position_at(uv));
}


float silhouette_guard(vec2 uv, float center_distance, vec2 pixel) {
	float d0 = distance_at(clamp(uv + vec2(pixel.x, 0.0), vec2(0.0), vec2(1.0)));
	float d1 = distance_at(clamp(uv - vec2(pixel.x, 0.0), vec2(0.0), vec2(1.0)));
	float d2 = distance_at(clamp(uv + vec2(0.0, pixel.y), vec2(0.0), vec2(1.0)));
	float d3 = distance_at(clamp(uv - vec2(0.0, pixel.y), vec2(0.0), vec2(1.0)));
	float delta = max(max(abs(d0 - center_distance), abs(d1 - center_distance)), max(abs(d2 - center_distance), abs(d3 - center_distance)));
	return 1.0 - smoothstep(silhouette_guard_m, silhouette_guard_m * 2.5, delta);
}


void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 source = textureLod(screen_texture, uv, 0.0).rgb;
	float distance_m = distance_at(uv);

	// Explicit depth hierarchy. Nothing below mid_start_m is touched.
	float mid = smoothstep(mid_start_m, max(mid_full_m, mid_start_m + 0.001), distance_m);
	float far = smoothstep(far_start_m, max(far_full_m, far_start_m + 0.001), distance_m);

	// Softness is deliberately secondary. Preserve depth discontinuities so Henry,
	// nearby poles and tree trunks stay graphic instead of bleeding into background.
	vec2 pixel = 1.0 / max(viewport_size, vec2(1.0));
	float blur_amount = smoothstep(blur_start_m, max(blur_end_m, blur_start_m + 0.001), distance_m) * blur_strength;
	float edge_guard = silhouette_guard(uv, distance_m, pixel * max(blur_radius_px, 1.0));
	float blur_lod = log2(max(blur_radius_px, 1.0));
	vec3 soft = textureLod(screen_texture, uv, blur_lod).rgb;
	vec3 color = mix(source, soft, blur_amount * edge_guard);

	float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
	float desat = clamp(mid * mid_desaturation + far * far_desaturation, 0.0, 1.0);
	color = mix(color, vec3(luma), desat);

	// Mid-ground first loses local value separation. Far-field compression stacks
	// on top so a facade reads as a broad painted mass rather than faded PBR detail.
	float compression = clamp(mid * mid_contrast_compression + far * far_contrast_compression, 0.0, 0.92);
	color = (color - vec3(0.5)) * (1.0 - compression) + vec3(0.5);

	// Lift dark architecture toward charcoal before it merges into cold paper.
	float dark_mask = 1.0 - smoothstep(0.16, 0.68, luma);
	float dark_lift = clamp(mid * mid_dark_value_lift + far * far_dark_value_lift, 0.0, 0.9);
	color += (vec3(1.0) - color) * dark_lift * dark_mask;

	// World-space horizon wash: no camera-fixed horizontal band.
	vec3 view_pos = view_position_at(uv);
	vec3 view_dir = normalize(view_pos);
	vec3 world_dir = normalize((INV_VIEW_MATRIX * vec4(view_dir, 0.0)).xyz);
	float horizon = 1.0 - smoothstep(0.0, horizon_band, abs(world_dir.y));

	float paper_mix = mid * mid_paper_mix + far * far_paper_mix;
	paper_mix += horizon * horizon_paper_boost * mid;
	paper_mix = clamp(paper_mix, 0.0, 0.94);
	color = mix(color, wash_color.rgb, paper_mix);

	ALBEDO = clamp(color, vec3(0.0), vec3(1.0));
	ALPHA = 1.0;
}