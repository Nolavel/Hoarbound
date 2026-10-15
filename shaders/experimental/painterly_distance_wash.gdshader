shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_test_disabled, depth_draw_never;

// Experimental Hoarbound painterly distance wash.
// Reference target: depth removes information aggressively. Near silhouettes stay
// crisp; mid-distance buildings lose local contrast/chroma; far architecture
// becomes a pale cold mass that can nearly merge with snow/sky. This is not DOF.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;

uniform float wash_start_m : hint_range(0.0, 100.0, 0.5) = 10.0;
uniform float wash_end_m : hint_range(10.0, 250.0, 1.0) = 72.0;
uniform float wash_curve : hint_range(0.25, 2.0, 0.01) = 0.68;
uniform float wash_strength : hint_range(0.0, 1.0, 0.01) = 0.82;
uniform vec4 wash_color : source_color = vec4(0.92, 0.94, 0.95, 1.0);

uniform float desaturation : hint_range(0.0, 1.0, 0.01) = 0.78;
uniform float contrast_compression : hint_range(0.0, 1.0, 0.01) = 0.60;
uniform float dark_value_lift : hint_range(0.0, 1.0, 0.01) = 0.44;

uniform float far_erase_start_m : hint_range(10.0, 200.0, 1.0) = 42.0;
uniform float far_erase_end_m : hint_range(20.0, 300.0, 1.0) = 95.0;
uniform float far_erase_strength : hint_range(0.0, 0.5, 0.01) = 0.16;

uniform float blur_start_m : hint_range(0.0, 150.0, 1.0) = 25.0;
uniform float blur_end_m : hint_range(10.0, 250.0, 1.0) = 85.0;
uniform float blur_strength : hint_range(0.0, 1.0, 0.01) = 0.33;
uniform float blur_radius_px : hint_range(0.0, 6.0, 0.1) = 3.0;
uniform float silhouette_guard_m : hint_range(0.5, 30.0, 0.5) = 6.0;
uniform vec2 viewport_size = vec2(1280.0, 720.0);

uniform float horizon_band : hint_range(0.01, 0.5, 0.01) = 0.16;
uniform float horizon_boost : hint_range(0.0, 0.5, 0.01) = 0.22;


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
		return far_erase_end_m * 2.0;
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

	float wash_linear = smoothstep(wash_start_m, max(wash_end_m, wash_start_m + 0.001), distance_m);
	float wash = pow(clamp(wash_linear, 0.0, 1.0), wash_curve);
	float far_erase = smoothstep(far_erase_start_m, max(far_erase_end_m, far_erase_start_m + 0.001), distance_m);

	// The references lose the horizon into paper/snow. Keep this tied to the
	// world horizon so camera pitch does not drag a visible screen-space band.
	vec3 view_pos = view_position_at(uv);
	vec3 view_dir = normalize(view_pos);
	vec3 world_dir = normalize((INV_VIEW_MATRIX * vec4(view_dir, 0.0)).xyz);
	float horizon = 1.0 - smoothstep(0.0, horizon_band, abs(world_dir.y));
	wash = clamp(wash + horizon * horizon_boost * sqrt(max(wash, 0.0)), 0.0, 1.0);

	// Softness is secondary. Preserve depth discontinuities so Henry, nearby
	// poles and tree trunks stay graphic instead of bleeding into the background.
	vec2 pixel = 1.0 / max(viewport_size, vec2(1.0));
	float blur_amount = smoothstep(blur_start_m, max(blur_end_m, blur_start_m + 0.001), distance_m) * blur_strength;
	float edge_guard = silhouette_guard(uv, distance_m, pixel * max(blur_radius_px, 1.0));
	float blur_lod = log2(max(blur_radius_px, 1.0));
	vec3 soft = textureLod(screen_texture, uv, blur_lod).rgb;
	vec3 color = mix(source, soft, blur_amount * edge_guard);

	float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
	color = mix(color, vec3(luma), wash * desaturation);

	// Compress local value range before whitening. This is the main painterly
	// simplification: a distant facade should read as one mass, not a faded PBR asset.
	color = (color - vec3(0.5)) * (1.0 - wash * contrast_compression) + vec3(0.5);

	// Dark architecture must lift much faster than snow/highlights. The reference
	// keeps a readable silhouette, but abandons near-black values with distance.
	float dark_mask = 1.0 - smoothstep(0.16, 0.68, luma);
	color += (vec3(1.0) - color) * (wash * dark_value_lift * dark_mask);

	// Final paper merge: moderate in the midground, decisive in the far field.
	float paper_mix = clamp(wash * wash_strength + far_erase * far_erase_strength, 0.0, 0.98);
	color = mix(color, wash_color.rgb, paper_mix);

	ALBEDO = clamp(color, vec3(0.0), vec3(1.0));
	ALPHA = 1.0;
}
