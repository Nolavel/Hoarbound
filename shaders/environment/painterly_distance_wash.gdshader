shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_test_disabled, depth_draw_never;

// Hoarbound painterly atmosphere pass for the production TPS camera.
// This is atmospheric value shaping, not a replacement for the surface-bound
// PainterlySurface material contract.
// Distance removes information in broad painted stages rather than simulating DOF.
// Near silhouettes stay crisp; distant architecture loses chroma and local detail,
// while world-stable pigment breakup and a restrained paper tooth prevent sterile fog.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;

uniform float mid_start_m : hint_range(0.0, 100.0, 0.5) = 18.0;
uniform float mid_full_m : hint_range(5.0, 150.0, 0.5) = 32.0;
uniform float far_start_m : hint_range(10.0, 200.0, 1.0) = 32.0;
uniform float far_full_m : hint_range(20.0, 300.0, 1.0) = 70.0;
uniform vec4 wash_color : source_color = vec4(0.90, 0.92, 0.94, 1.0);

uniform float mid_desaturation : hint_range(0.0, 1.0, 0.01) = 0.34;
uniform float far_desaturation : hint_range(0.0, 1.0, 0.01) = 0.48;
uniform float mid_contrast_compression : hint_range(0.0, 1.0, 0.01) = 0.24;
uniform float far_contrast_compression : hint_range(0.0, 1.0, 0.01) = 0.40;
uniform float mid_dark_value_lift : hint_range(0.0, 1.0, 0.01) = 0.10;
uniform float far_dark_value_lift : hint_range(0.0, 1.0, 0.01) = 0.32;
uniform float mid_ink_hold : hint_range(0.0, 0.5, 0.01) = 0.22;
uniform float mid_paper_mix : hint_range(0.0, 1.0, 0.01) = 0.27;
uniform float far_paper_mix : hint_range(0.0, 1.0, 0.01) = 0.44;

uniform float blur_start_m : hint_range(0.0, 150.0, 1.0) = 26.0;
uniform float blur_end_m : hint_range(10.0, 250.0, 1.0) = 70.0;
uniform float blur_strength : hint_range(0.0, 1.0, 0.01) = 0.16;
uniform float blur_radius_px : hint_range(0.0, 6.0, 0.1) = 2.2;
uniform float silhouette_guard_m : hint_range(0.5, 30.0, 0.5) = 6.0;
uniform vec2 viewport_size = vec2(1600.0, 1000.0);

// Share of the wash the sky takes, like Environment.fog_sky_affect: the authored sky and horizon haze stay.
uniform float sky_affect : hint_range(0.0, 1.0, 0.01) = 0.1;

uniform float horizon_band : hint_range(0.01, 0.5, 0.01) = 0.16;
uniform float horizon_paper_boost : hint_range(0.0, 0.5, 0.01) = 0.08;

uniform float paper_grain_strength : hint_range(0.0, 0.08, 0.001) = 0.024;
uniform float paper_grain_scale_px : hint_range(1.0, 8.0, 0.25) = 2.25;
uniform float blotch_scale : hint_range(0.01, 1.0, 0.01) = 0.11;
uniform float blotch_mix_variation : hint_range(0.0, 0.5, 0.01) = 0.23;
uniform float blotch_value_variation : hint_range(0.0, 0.12, 0.005) = 0.045;
uniform float dry_brush_scale : hint_range(0.1, 4.0, 0.05) = 0.65;
uniform float dry_brush_strength : hint_range(0.0, 0.4, 0.01) = 0.16;

uniform vec4 warm_window_color : source_color = vec4(0.22, 0.16, 0.12, 1.0);
uniform float warm_window_strength : hint_range(0.0, 1.0, 0.01) = 0.78;
uniform float warm_window_sparsity : hint_range(0.80, 0.995, 0.005) = 0.94;
uniform float warm_window_near_m : hint_range(0.0, 100.0, 1.0) = 20.0;
uniform float warm_window_far_m : hint_range(10.0, 150.0, 1.0) = 62.0;
uniform vec2 warm_window_cell_m = vec2(2.8, 2.2);

// CI-only diagnostic modes used by the capture harness to prove that the
// fullscreen pass is drawing, depth is readable and material masks are active.
uniform int debug_mode = 0;


void vertex() {
	// Godot 4.3+ uses reverse-Z, so the fullscreen quad belongs at clip-space Z=1.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}


float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


float value_noise_2d(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	vec2 blend = local * local * (3.0 - 2.0 * local);
	float n00 = hash21(cell);
	float n10 = hash21(cell + vec2(1.0, 0.0));
	float n01 = hash21(cell + vec2(0.0, 1.0));
	float n11 = hash21(cell + vec2(1.0, 1.0));
	return mix(mix(n00, n10, blend.x), mix(n01, n11, blend.x), blend.y);
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


vec3 world_position_at(vec2 uv, mat4 inverse_projection, mat4 inverse_view) {
	return (inverse_view * vec4(view_position_at(uv, inverse_projection), 1.0)).xyz;
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


float window_shape(vec2 grid_position) {
	vec2 centered = abs(fract(grid_position) - vec2(0.5));
	float horizontal = 1.0 - smoothstep(0.16, 0.23, centered.x);
	float vertical = 1.0 - smoothstep(0.18, 0.29, centered.y);
	return horizontal * vertical;
}


void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 source = textureLod(screen_texture, uv, 0.0).rgb;
	float raw_depth = textureLod(depth_texture, uv, 0.0).r;
	float has_geometry = step(0.000001, raw_depth);
	float distance_m = distance_at(uv, INV_PROJECTION_MATRIX);

	if (debug_mode == 1) {
		ALBEDO = mix(source, vec3(1.0, 0.0, 1.0), 0.78);
	} else if (debug_mode == 2) {
		float depth_band = clamp(distance_m / max(far_full_m, 1.0), 0.0, 1.0);
		ALBEDO = vec3(depth_band);
	} else {
		// Keep the first ~18 m effectively untouched, then remove information in
		// readable painted planes. Mid-ground ink stays darker than the far wash.
		float sky_scope = mix(sky_affect, 1.0, has_geometry);
		float mid = smoothstep(mid_start_m, max(mid_full_m, mid_start_m + 0.001), distance_m) * sky_scope;
		float far = smoothstep(far_start_m, max(far_full_m, far_start_m + 0.001), distance_m) * sky_scope;
		float mid_only = mid * (1.0 - far * 0.72);

		vec2 pixel = 1.0 / max(viewport_size, vec2(1.0));
		float blur_amount = smoothstep(blur_start_m, max(blur_end_m, blur_start_m + 0.001), distance_m) * blur_strength;
		float edge_guard = silhouette_guard(uv, distance_m, pixel * max(blur_radius_px, 1.0), INV_PROJECTION_MATRIX);
		float blur_lod = log2(max(blur_radius_px, 1.0));
		vec3 soft = textureLod(screen_texture, uv, blur_lod).rgb;
		vec3 color = mix(source, soft, blur_amount * edge_guard);

		float source_luma = dot(source, vec3(0.2126, 0.7152, 0.0722));
		float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
		float desat = clamp(mid * mid_desaturation + far * far_desaturation, 0.0, 1.0);
		color = mix(color, vec3(luma), desat);

		float compression = clamp(mid * mid_contrast_compression + far * far_contrast_compression, 0.0, 0.92);
		color = (color - vec3(0.5)) * (1.0 - compression) + vec3(0.5);

		float dark_mask = 1.0 - smoothstep(0.16, 0.68, luma);
		color *= 1.0 - mid_only * mid_ink_hold * dark_mask;
		float dark_lift = clamp(mid * mid_dark_value_lift + far * far_dark_value_lift, 0.0, 0.9);
		color += (vec3(1.0) - color) * dark_lift * dark_mask;

		vec3 view_pos = view_position_at(uv, INV_PROJECTION_MATRIX);
		vec3 view_dir = normalize(view_pos);
		vec3 world_dir = normalize((INV_VIEW_MATRIX * vec4(view_dir, 0.0)).xyz);
		vec3 world_pos = world_position_at(uv, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
		float horizon = 1.0 - smoothstep(0.0, horizon_band, abs(world_dir.y));

		// The low-frequency pigment field lives in world space, so it does not swim
		// over buildings when the TPS camera moves.
		vec2 pigment_uv = vec2(
			dot(world_pos, vec3(blotch_scale, blotch_scale * 0.64, blotch_scale * 0.27)),
			dot(world_pos, vec3(-blotch_scale * 0.36, blotch_scale * 1.18, blotch_scale * 0.82))
		);
		float blotch = value_noise_2d(pigment_uv);
		float pigment_scope = clamp(mid * 0.85 + far * 0.35, 0.0, 1.0) * has_geometry;

		float paper_mix = mid * mid_paper_mix + far * far_paper_mix;
		paper_mix += horizon * horizon_paper_boost * mid;
		paper_mix *= 1.0 + (blotch - 0.5) * 2.0 * blotch_mix_variation * pigment_scope;
		paper_mix = clamp(paper_mix, 0.0, 0.90);
		color = mix(color, wash_color.rgb, paper_mix);
		color += vec3((blotch - 0.5) * 2.0 * blotch_value_variation * pigment_scope);

		// Sparse anisotropic pigment catches dark mid-ground masses like a dry brush.
		vec2 dry_uv = vec2(pigment_uv.x * dry_brush_scale * 6.0, pigment_uv.y * dry_brush_scale * 1.35);
		float dry_field = value_noise_2d(dry_uv + vec2(17.3, 4.9));
		float dry_brush = smoothstep(0.64, 0.84, dry_field + (blotch - 0.5) * 0.18);
		float dry_scope = dry_brush * mid_only * dark_mask * has_geometry;
		color *= 1.0 - dry_scope * dry_brush_strength;

		// Rare procedural window apertures are evaluated in world space and only on
		// continuous, facade-like surfaces. Existing warm highlights are protected.
		vec3 surface_cross = cross(dFdx(world_pos), dFdy(world_pos));
		float surface_cross_length = length(surface_cross);
		vec3 surface_normal = surface_cross / max(surface_cross_length, 0.0001);
		float facade = (1.0 - smoothstep(0.34, 0.72, abs(surface_normal.y))) * step(0.0001, surface_cross_length);
		bool faces_z = abs(surface_normal.z) >= abs(surface_normal.x);
		vec2 facade_position = faces_z ? vec2(world_pos.x, world_pos.y) : vec2(world_pos.z, world_pos.y);
		vec2 window_grid = facade_position / max(warm_window_cell_m, vec2(0.1));
		vec2 window_cell = floor(window_grid);
		float orientation_seed = faces_z ? 19.0 : 43.0;
		float rare_cell = step(warm_window_sparsity, hash21(window_cell + vec2(orientation_seed, 7.0)));
		float aperture = window_shape(window_grid) * rare_cell;
		float window_range = smoothstep(warm_window_near_m, warm_window_near_m + 5.0, distance_m);
		window_range *= 1.0 - smoothstep(warm_window_far_m - 10.0, warm_window_far_m, distance_m);
		float wall_value = smoothstep(0.13, 0.32, source_luma) * (1.0 - smoothstep(0.72, 0.92, source_luma));
		float existing_warm = smoothstep(0.015, 0.10, source.r - source.b) * smoothstep(0.16, 0.58, source_luma);
		float warm_window = max(aperture * facade * wall_value * edge_guard, existing_warm * 0.7);
		warm_window *= window_range * has_geometry;
		float warm_energy = mix(0.72, 1.0, hash21(window_cell + vec2(3.0, 71.0)));
		vec3 warm_target = warm_window_color.rgb * warm_energy;
		color = mix(color, warm_target, warm_window * warm_window_strength);

		// Paper tooth stays subtle and screen-stable: this is the sheet, not another
		// layer of world material noise. Near gameplay readability is mostly intact.
		vec2 grain_cell = floor((uv * viewport_size) / max(paper_grain_scale_px, 1.0));
		float grain = hash21(grain_cell + vec2(5.0, 113.0));
		float grain_scope = clamp(0.30 + mid * 0.35 + far * 0.35, 0.0, 1.0);
		color *= 1.0 + (grain - 0.5) * 2.0 * paper_grain_strength * grain_scope;

		if (debug_mode == 3) {
			ALBEDO = vec3(grain);
		} else if (debug_mode == 4) {
			ALBEDO = vec3(blotch, dry_brush, warm_window);
		} else {
			ALBEDO = clamp(color, vec3(0.0), vec3(1.0));
		}
	}
	ALPHA = 1.0;
}

