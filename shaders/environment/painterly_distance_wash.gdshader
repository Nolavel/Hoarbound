shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_test_disabled, depth_draw_never;

// Hoarbound painterly atmosphere pass for the production TPS camera.
// This is atmospheric value shaping, not a replacement for the surface-bound
// PainterlySurface material contract.
// Distance removes information in broad painted stages rather than simulating DOF.
// Near silhouettes stay readable; distant architecture loses chroma and local detail.
// Broad world-stable wash fronts, drying rims, two-scale pigment and a permanent
// paper tooth keep the result painted without turning it into a universal outline pass.

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
uniform float mid_dark_value_lift : hint_range(0.0, 1.0, 0.01) = 0.08;
uniform float far_dark_value_lift : hint_range(0.0, 1.0, 0.01) = 0.32;
uniform float mid_ink_hold : hint_range(0.0, 0.5, 0.01) = 0.28;
uniform float mid_paper_mix : hint_range(0.0, 1.0, 0.01) = 0.27;
uniform float far_paper_mix : hint_range(0.0, 1.0, 0.01) = 0.44;
uniform float value_steps : hint_range(4.0, 12.0, 1.0) = 7.0;
uniform float value_terrace_strength : hint_range(0.0, 0.5, 0.01) = 0.18;

uniform float blur_start_m : hint_range(0.0, 150.0, 1.0) = 26.0;
uniform float blur_end_m : hint_range(10.0, 250.0, 1.0) = 70.0;
uniform float blur_strength : hint_range(0.0, 1.0, 0.01) = 0.16;
uniform float blur_radius_px : hint_range(0.0, 6.0, 0.1) = 2.2;
uniform float silhouette_guard_m : hint_range(0.5, 30.0, 0.5) = 6.0;
uniform float edge_bleed_strength : hint_range(0.0, 0.25, 0.005) = 0.095;
uniform float pigment_pool_strength : hint_range(0.0, 0.35, 0.005) = 0.18;
uniform float drying_rim_strength : hint_range(0.0, 0.25, 0.005) = 0.08;
uniform float internal_ink_strength : hint_range(0.0, 0.25, 0.005) = 0.09;
uniform vec2 viewport_size = vec2(1600.0, 1000.0);

// Share of the wash the sky takes, like Environment.fog_sky_affect: the authored sky and horizon haze stay.
uniform float sky_affect : hint_range(0.0, 1.0, 0.01) = 0.1;
// Atmospheric wash strength, set by PainterlyAtmospherePass from snowfall.
uniform float wash_strength : hint_range(0.0, 1.0, 0.01) = 1.0;
// Permanent sheet identity. It is deliberately independent of snowfall.
uniform float paper_strength : hint_range(0.0, 1.5, 0.01) = 1.0;
uniform float paper_base_mix : hint_range(0.0, 0.12, 0.001) = 0.035;

uniform float horizon_band : hint_range(0.01, 0.5, 0.01) = 0.16;
uniform float horizon_paper_boost : hint_range(0.0, 0.5, 0.01) = 0.08;

uniform float paper_grain_strength : hint_range(0.0, 0.08, 0.001) = 0.024;
uniform float paper_grain_scale_px : hint_range(1.0, 8.0, 0.25) = 2.25;
uniform float paper_fiber_strength : hint_range(0.0, 0.04, 0.001) = 0.008;
uniform float blotch_scale : hint_range(0.01, 1.0, 0.01) = 0.11;
uniform float blotch_mix_variation : hint_range(0.0, 0.5, 0.01) = 0.23;
uniform float blotch_value_variation : hint_range(0.0, 0.12, 0.005) = 0.045;
uniform float granulation_scale : hint_range(1.0, 8.0, 0.25) = 3.75;
uniform float granulation_strength : hint_range(0.0, 0.2, 0.005) = 0.065;
uniform float wash_edge_scale : hint_range(0.005, 0.2, 0.005) = 0.045;
uniform float wash_edge_variation_m : hint_range(0.0, 12.0, 0.25) = 4.0;
uniform float dry_brush_scale : hint_range(0.1, 4.0, 0.05) = 0.65;
uniform float dry_brush_strength : hint_range(0.0, 0.4, 0.01) = 0.16;

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


float distance_at(vec2 uv, mat4 inverse_projection) {
	float raw_depth = textureLod(depth_texture, uv, 0.0).r;
	// Reverse-Z: 0 is the far plane/sky, 1 is the near plane.
	if (raw_depth <= 0.000001) {
		return far_full_m * 2.0;
	}
	return max(-view_position_at(uv, inverse_projection).z, 0.0);
}


float depth_discontinuity(vec2 uv, float center_distance, vec2 pixel, mat4 inverse_projection) {
	float d0 = distance_at(clamp(uv + vec2(pixel.x, 0.0), vec2(0.0), vec2(1.0)), inverse_projection);
	float d1 = distance_at(clamp(uv - vec2(pixel.x, 0.0), vec2(0.0), vec2(1.0)), inverse_projection);
	float d2 = distance_at(clamp(uv + vec2(0.0, pixel.y), vec2(0.0), vec2(1.0)), inverse_projection);
	float d3 = distance_at(clamp(uv - vec2(0.0, pixel.y), vec2(0.0), vec2(1.0)), inverse_projection);
	float delta = max(max(abs(d0 - center_distance), abs(d1 - center_distance)), max(abs(d2 - center_distance), abs(d3 - center_distance)));
	return smoothstep(silhouette_guard_m, silhouette_guard_m * 2.5, delta);
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
		vec3 view_pos = view_position_at(uv, INV_PROJECTION_MATRIX);
		vec3 view_dir = normalize(view_pos);
		vec3 world_dir = normalize((INV_VIEW_MATRIX * vec4(view_dir, 0.0)).xyz);
		vec3 world_pos = (INV_VIEW_MATRIX * vec4(view_pos, 1.0)).xyz;

		// Break the clean distance bands into broad wet-on-wet fronts. One low-frequency
		// field offsets the thresholds by a few metres and stays fixed to the city.
		vec2 wash_edge_uv = vec2(
			world_pos.x + world_pos.z * 0.31,
			world_pos.z - world_pos.x * 0.27
		) * wash_edge_scale;
		float wash_edge_noise = value_noise_2d(wash_edge_uv);
		float wash_offset_m = (wash_edge_noise - 0.5) * 2.0 * wash_edge_variation_m * has_geometry;

		// Keep the first ~18 m effectively untouched, then remove information in
		// readable but irregular painted planes. Mid-ground ink stays darker than the far wash.
		float sky_scope = mix(sky_affect, 1.0, has_geometry);
		float mid_start = mid_start_m + wash_offset_m;
		float mid_full = max(mid_full_m + wash_offset_m * 0.65, mid_start + 0.001);
		float far_start = far_start_m + wash_offset_m * 0.85;
		float far_full = max(far_full_m + wash_offset_m * 1.25, far_start + 0.001);
		float mid_transition = smoothstep(mid_start, mid_full, distance_m);
		float far_transition = smoothstep(far_start, far_full, distance_m);
		float mid = mid_transition * sky_scope;
		float far = far_transition * sky_scope;
		float mid_only = mid * (1.0 - far * 0.72);

		vec2 pixel = 1.0 / max(viewport_size, vec2(1.0));
		float blur_start = blur_start_m + wash_offset_m * 0.5;
		float blur_end = max(blur_end_m + wash_offset_m * 0.75, blur_start + 0.001);
		float blur_amount = smoothstep(blur_start, blur_end, distance_m) * blur_strength;
		float depth_edge = depth_discontinuity(uv, distance_m, pixel * max(blur_radius_px, 1.0), INV_PROJECTION_MATRIX);
		float edge_guard = 1.0 - depth_edge;
		float edge_range = smoothstep(mid_start_m - 2.0, mid_start_m + 6.0, distance_m);
		edge_range *= 1.0 - smoothstep(far_full_m - 10.0, far_full_m + 12.0, distance_m);
		float edge_breakup = 0.55 + wash_edge_noise * 0.45;
		float edge_scope = depth_edge * edge_range * edge_breakup * has_geometry;
		float blur_lod = log2(max(blur_radius_px, 1.0));
		vec3 soft = textureLod(screen_texture, uv, blur_lod).rgb;
		float soft_mix = clamp(blur_amount * edge_guard + edge_scope * edge_bleed_strength, 0.0, 1.0);
		vec3 color = mix(source, soft, soft_mix);

		float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
		float desat = clamp(mid * mid_desaturation + far * far_desaturation, 0.0, 1.0);
		color = mix(color, vec3(luma), desat);

		float compression = clamp(mid * mid_contrast_compression + far * far_contrast_compression, 0.0, 0.92);
		color = (color - vec3(0.5)) * (1.0 - compression) + vec3(0.5);

		float dark_mask = 1.0 - smoothstep(0.16, 0.68, luma);
		color *= 1.0 - mid_only * mid_ink_hold * dark_mask;
		float dark_lift = clamp(mid * mid_dark_value_lift + far * far_dark_value_lift, 0.0, 0.9);
		color += (vec3(1.0) - color) * dark_lift * dark_mask;

		float horizon = 1.0 - smoothstep(0.0, horizon_band, abs(world_dir.y));

		// The low-frequency pigment field lives in world space, so it does not swim
		// over buildings when the TPS camera moves.
		vec2 pigment_uv = vec2(
			dot(world_pos, vec3(blotch_scale, blotch_scale * 0.64, blotch_scale * 0.27)),
			dot(world_pos, vec3(-blotch_scale * 0.36, blotch_scale * 1.18, blotch_scale * 0.82))
		);
		float blotch = value_noise_2d(pigment_uv);
		// A second, smaller world-space field gives pigment granulation without
		// screen-space crawling. Its cells are still metres wide, not pixel noise.
		float granulation = value_noise_2d(
			pigment_uv * vec2(granulation_scale, granulation_scale * 0.78) + vec2(29.7, 7.1)
		);
		float granulation_deposit = smoothstep(0.50, 0.82, granulation + (blotch - 0.5) * 0.16);
		float pigment_scope = clamp(mid * 0.85 + far * 0.35, 0.0, 1.0) * has_geometry;

		// The references are built from a small number of broad value families.
		// A weak, world-jittered terrace collapses digital gradients without hard posterisation.
		float terrace_luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
		float terrace_denominator = max(value_steps - 1.0, 1.0);
		float terrace_input = clamp(terrace_luma + (granulation - 0.5) * 0.04, 0.0, 1.0);
		float stepped_luma = floor(terrace_input * terrace_denominator + 0.5) / terrace_denominator;
		vec3 terraced_color = color + vec3(stepped_luma - terrace_luma);
		float terrace_scope = clamp(mid_only * 0.95 + far * 0.28, 0.0, 1.0) * has_geometry;
		color = mix(color, terraced_color, value_terrace_strength * terrace_scope);

		float paper_mix = mid * mid_paper_mix + far * far_paper_mix;
		paper_mix += horizon * horizon_paper_boost * mid;
		paper_mix *= 1.0 + (blotch - 0.5) * 2.0 * blotch_mix_variation * pigment_scope;
		paper_mix = clamp(paper_mix, 0.0, 0.90);
		color = mix(color, wash_color.rgb, paper_mix);
		color += vec3((blotch - 0.5) * 2.0 * blotch_value_variation * pigment_scope);
		float granulation_weight = mix(0.28, 1.0, dark_mask);
		color *= 1.0 - granulation_deposit * pigment_scope * granulation_strength * granulation_weight;

		// A broken dark deposit on selected geometry edges, followed by the restrained
		// soft mix above, reads as pooling plus wet bleed rather than a toon outline.
		float pool_breakup = smoothstep(0.20, 0.78, blotch * 0.72 + wash_edge_noise * 0.28);
		float pigment_pool = edge_scope * pool_breakup;
		float pool_weight = mix(0.55, 1.0, dark_mask);
		color *= 1.0 - pigment_pool * pigment_pool_strength * pool_weight;

		// A narrow broken deposit follows the irregular drying front of each broad wash.
		// Light snow receives only a trace; dark architecture holds most of the rim.
		float mid_front = pow(clamp(4.0 * mid_transition * (1.0 - mid_transition), 0.0, 1.0), 4.0);
		float far_front = pow(clamp(4.0 * far_transition * (1.0 - far_transition), 0.0, 1.0), 4.0);
		float rim_breakup = smoothstep(0.24, 0.82, blotch * 0.56 + granulation * 0.44);
		float drying_rim = max(mid_front, far_front * 0.72) * rim_breakup * has_geometry;
		color *= 1.0 - drying_rim * drying_rim_strength * mix(0.20, 1.0, dark_mask);

		// Screen derivatives find authored facade divisions and window frames without
		// another texture sample. Depth silhouettes are excluded to avoid a toon outline.
		float luma_gradient = fwidth(luma);
		float internal_ink = smoothstep(0.018, 0.095, luma_gradient);
		internal_ink *= mid_only * has_geometry * (1.0 - depth_edge * 0.85);
		internal_ink *= mix(0.45, 1.0, dark_mask) * mix(0.72, 1.0, granulation_deposit);
		color *= 1.0 - internal_ink * internal_ink_strength;

		// Sparse anisotropic pigment catches dark mid-ground masses like a dry brush.
		vec2 dry_uv = vec2(pigment_uv.x * dry_brush_scale * 6.0, pigment_uv.y * dry_brush_scale * 1.35);
		float dry_field = value_noise_2d(dry_uv + vec2(17.3, 4.9));
		float dry_brush = smoothstep(0.64, 0.84, dry_field + (blotch - 0.5) * 0.18);
		float dry_scope = dry_brush * mid_only * dark_mask * has_geometry;
		color *= 1.0 - dry_scope * dry_brush_strength;

		// Paper is applied after the weather-driven atmosphere mix. It therefore stays
		// present in calm weather instead of disappearing with the snowstorm wash.
		vec2 paper_pixel = uv * viewport_size;
		vec2 grain_cell = floor(paper_pixel / max(paper_grain_scale_px, 1.0));
		float grain = hash21(grain_cell + vec2(5.0, 113.0));
		vec2 fiber_cell = floor(vec2((paper_pixel.x + paper_pixel.y * 0.18) / 13.0, paper_pixel.y / 2.0));
		float fiber = hash21(fiber_cell + vec2(211.0, 37.0));
		float grain_scope = clamp(0.60 + mid * 0.18 + far * 0.22, 0.0, 1.0);
		vec3 final_color = mix(source, clamp(color, vec3(0.0), vec3(1.0)), wash_strength);
		final_color = mix(final_color, wash_color.rgb, paper_base_mix * paper_strength * grain_scope);
		float paper_modulation = (grain - 0.5) * 2.0 * paper_grain_strength;
		paper_modulation += (fiber - 0.5) * 2.0 * paper_fiber_strength;
		final_color *= 1.0 + paper_modulation * paper_strength * grain_scope;

		if (debug_mode == 3) {
			float paper_probe = clamp(0.5 + (grain - 0.5) * 0.75 + (fiber - 0.5) * 0.25, 0.0, 1.0);
			ALBEDO = vec3(paper_probe);
		} else if (debug_mode == 4) {
			ALBEDO = vec3(drying_rim, granulation_deposit * pigment_scope, internal_ink);
		} else if (debug_mode == 5) {
			ALBEDO = vec3(wash_edge_noise, pigment_pool, edge_scope);
		} else {
			ALBEDO = clamp(final_color, vec3(0.0), vec3(1.0));
		}
	}
	ALPHA = 1.0;
}


