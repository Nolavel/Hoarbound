shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_test_disabled, depth_draw_never;

// Experimental Hoarbound painterly distance wash.
// Distance removes information in broad painted stages rather than simulating DOF.
// Near silhouettes stay crisp; distant architecture loses chroma, local contrast,
// dark values and finally merges toward a cold paper/snow tone.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;

uniform float mid_start_m : hint_range(0.0, 100.0, 0.5) = 18.0;
uniform float mid_full_m : hint_range(5.0, 150.0, 0.5) = 32.0;
uniform float far_start_m : hint_range(10.0, 200.0, 1.0) = 32.0;
uniform float far_full_m : hint_range(20.0, 300.0, 1.0) = 70.0;
uniform vec4 wash_color : source_color = vec4(0.90, 0.92, 0.94, 1.0);

uniform float mid_desaturation : hint_range(0.0, 1.0, 0.01) = 0.45;
uniform float far_desaturation : hint_range(0.0, 1.0, 0.01) = 0.45;
uniform float mid_contrast_compression : hint_range(0.0, 1.0, 0.01) = 0.36;
uniform float far_contrast_compression : hint_range(0.0, 1.0, 0.01) = 0.38;
uniform float mid_dark_value_lift : hint_range(0.0, 1.0, 0.01) = 0.32;
uniform float far_dark_value_lift : hint_range(0.0, 1.0, 0.01) = 0.34;
uniform float mid_paper_mix : hint_range(0.0, 1.0, 0.01) = 0.38;
uniform float far_paper_mix : hint_range(0.0, 1.0, 0.01) = 0.42;

uniform float blur_start_m : hint_range(0.0, 150.0, 1.0) = 26.0;
uniform float blur_end_m : hint_range(10.0, 250.0, 1.0) = 70.0;
uniform float blur_strength : hint_range(0.0, 1.0, 0.01) = 0.18;
uniform float blur_radius_px : hint_range(0.0, 6.0, 0.1) = 2.4;
uniform float silhouette_guard_m : hint_range(0.5, 30.0, 0.5) = 6.0;
uniform vec2 viewport_size = vec2(1600.0, 1000.0);

uniform float horizon_band : hint_range(0.01, 0.5, 0.01) = 0.16;
uniform float horizon_paper_boost : hint_range(0.0, 0.5, 0.01) = 0.08;

// CI-only diagnostic modes used by the capture harness to prove that the
// fullscreen pass is actually drawing and that the depth buffer is readable.
uniform int debug_mode = 0;


void vertex() {
	// Godot 4.3+ uses reverse-Z, so the fullscreen quad belongs at clip-space Z=1.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}


vec3 view_position_at(vec2 uv, mat4 inverse_projection) {
	float raw_depth = textureLod(depth_texture, uv, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, raw_depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, raw_depth);
#endif
	vec4 view = inverse_projection * vec4(ndc, 1.0);
	float safe_w = abs(view.w) > 0.000001 ? view.w : 1.0;
	return view.xyz / safe_w;
}


float distance_at(vec2 uv, mat4 inverse_projection) {
	float raw_depth = textureLod(depth_texture, uv, 0.0).r;
	// Reverse-Z: 0 is the far plane/sky, 1 is the near plane.
	if (raw_depth <= 0.000001) {
		return far_full_m * 2.0;
	}
	return max(-view_position_at(uv, inverse_projection).z, 0.0);
}


float silhouette_guard(vec2 uv, float center_distance, vec2 pixel, mat4 inverse_projection) {
	float d0 = distance_at(clamp(uv + vec2(pixel.x, 0.0), vec2(0.0), vec2(1.0)), inverse_projection);
	float d1 = distance_at(clamp(uv - vec2(pixel.x, 0.0), vec2(0.0), vec2(1.0)), inverse_projection);
	float d2 = distance_at(clamp(uv + vec2(0.0, pixel.y), vec2(0.0), vec2(1.0)), inverse_projection);
	float d3 = distance_at(clamp(uv - vec2(0.0, pixel.y), vec2(0.0), vec2(1.0)), inverse_projection);
	float delta = max(max(abs(d0 - center_distance), abs(d1 - center_distance)), max(abs(d2 - center_distance), abs(d3 - center_distance)));
	return 1.0 - smoothstep(silhouette_guard_m, silhouette_guard_m * 2.5, delta);
}


void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 source = textureLod(screen_texture, uv, 0.0).rgb;
	float distance_m = distance_at(uv, INV_PROJECTION_MATRIX);

	if (debug_mode == 1) {
		ALBEDO = mix(source, vec3(1.0, 0.0, 1.0), 0.78);
	} else if (debug_mode == 2) {
		float depth_band = clamp(distance_m / max(far_full_m, 1.0), 0.0, 1.0);
		ALBEDO = vec3(depth_band);
	} else {

	// Keep the first ~18 m effectively untouched, then remove information quickly
	// enough that a 20-70 m street view visibly separates into painted depth planes.
	float mid = smoothstep(mid_start_m, max(mid_full_m, mid_start_m + 0.001), distance_m);
	float far = smoothstep(far_start_m, max(far_full_m, far_start_m + 0.001), distance_m);

	vec2 pixel = 1.0 / max(viewport_size, vec2(1.0));
	float blur_amount = smoothstep(blur_start_m, max(blur_end_m, blur_start_m + 0.001), distance_m) * blur_strength;
	float edge_guard = silhouette_guard(uv, distance_m, pixel * max(blur_radius_px, 1.0), INV_PROJECTION_MATRIX);
	float blur_lod = log2(max(blur_radius_px, 1.0));
	vec3 soft = textureLod(screen_texture, uv, blur_lod).rgb;
	vec3 color = mix(source, soft, blur_amount * edge_guard);

	float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
	float desat = clamp(mid * mid_desaturation + far * far_desaturation, 0.0, 1.0);
	color = mix(color, vec3(luma), desat);

	float compression = clamp(mid * mid_contrast_compression + far * far_contrast_compression, 0.0, 0.92);
	color = (color - vec3(0.5)) * (1.0 - compression) + vec3(0.5);

	float dark_mask = 1.0 - smoothstep(0.16, 0.68, luma);
	float dark_lift = clamp(mid * mid_dark_value_lift + far * far_dark_value_lift, 0.0, 0.9);
	color += (vec3(1.0) - color) * dark_lift * dark_mask;

	vec3 view_pos = view_position_at(uv, INV_PROJECTION_MATRIX);
	vec3 view_dir = normalize(view_pos);
	vec3 world_dir = normalize((INV_VIEW_MATRIX * vec4(view_dir, 0.0)).xyz);
	float horizon = 1.0 - smoothstep(0.0, horizon_band, abs(world_dir.y));

	float paper_mix = mid * mid_paper_mix + far * far_paper_mix;
	paper_mix += horizon * horizon_paper_boost * mid;
	paper_mix = clamp(paper_mix, 0.0, 0.90);
	color = mix(color, wash_color.rgb, paper_mix);

		ALBEDO = clamp(color, vec3(0.0), vec3(1.0));
	}
	ALPHA = 1.0;
}
