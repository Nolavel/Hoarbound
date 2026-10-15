shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_test_disabled, depth_draw_never;

// Experimental Hoarbound painterly distance wash.
// Goal: reproduce the reference hierarchy where depth removes information:
// distant values lift toward cold paper, chroma and contrast compress, and only
// a very small amount of softness appears. This is not camera DOF.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;

uniform float wash_start_m : hint_range(0.0, 100.0, 0.5) = 18.0;
uniform float wash_end_m : hint_range(10.0, 250.0, 1.0) = 95.0;
uniform float wash_strength : hint_range(0.0, 1.0, 0.01) = 0.72;
uniform vec4 wash_color : source_color = vec4(0.86, 0.89, 0.91, 1.0);

uniform float desaturation : hint_range(0.0, 1.0, 0.01) = 0.58;
uniform float contrast_compression : hint_range(0.0, 1.0, 0.01) = 0.34;
uniform float dark_value_lift : hint_range(0.0, 1.0, 0.01) = 0.18;

uniform float blur_start_m : hint_range(0.0, 150.0, 1.0) = 28.0;
uniform float blur_end_m : hint_range(10.0, 250.0, 1.0) = 105.0;
uniform float blur_strength : hint_range(0.0, 1.0, 0.01) = 0.24;
uniform float blur_radius_px : hint_range(0.0, 6.0, 0.1) = 2.2;
uniform float silhouette_guard_m : hint_range(0.5, 30.0, 0.5) = 6.0;
uniform vec2 viewport_size = vec2(1280.0, 720.0);

uniform float horizon_band : hint_range(0.01, 0.5, 0.01) = 0.13;
uniform float horizon_boost : hint_range(0.0, 0.5, 0.01) = 0.14;


void vertex() {
	// QuadMesh is authored at 2x2, so its XY already spans clip space.
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
		return wash_end_m * 2.0;
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
	float wash = smoothstep(wash_start_m, max(wash_end_m, wash_start_m + 0.001), distance_m);

	// World-space horizon boost: it follows camera pitch instead of sticking to
	// a fixed scanline. This is the reference's white-paper dissolution near the
	// horizon, not extra fog density everywhere.
	vec3 view_pos = view_position_at(uv);
	vec3 view_dir = normalize(view_pos);
	vec3 world_dir = normalize((INV_VIEW_MATRIX * vec4(view_dir, 0.0)).xyz);
	float horizon = 1.0 - smoothstep(0.0, horizon_band, abs(world_dir.y));
	wash = clamp(wash + horizon * horizon_boost * sqrt(max(wash, 0.0)), 0.0, 1.0);

	// Tiny far-field softness. Mip sampling is disabled at depth discontinuities
	// so Henry and near silhouettes do not bleed into the washed background.
	vec2 pixel = 1.0 / max(viewport_size, vec2(1.0));
	float blur_amount = smoothstep(blur_start_m, max(blur_end_m, blur_start_m + 0.001), distance_m) * blur_strength;
	float edge_guard = silhouette_guard(uv, distance_m, pixel * max(blur_radius_px, 1.0));
	float blur_lod = log2(max(blur_radius_px, 1.0));
	vec3 soft = textureLod(screen_texture, uv, blur_lod).rgb;
	vec3 color = mix(source, soft, blur_amount * edge_guard);

	float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
	color = mix(color, vec3(luma), wash * desaturation);
	color = (color - vec3(0.5)) * (1.0 - wash * contrast_compression) + vec3(0.5);

	// Lift dark distant masses more than snow/highlights. This is what turns a
	// black building into a grey silhouette before it dissolves into the paper.
	float dark_mask = 1.0 - smoothstep(0.20, 0.72, luma);
	color += (vec3(1.0) - color) * (wash * dark_value_lift * dark_mask);
	color = mix(color, wash_color.rgb, wash * wash_strength);

	ALBEDO = clamp(color, vec3(0.0), vec3(1.0));
	ALPHA = 1.0;
}
