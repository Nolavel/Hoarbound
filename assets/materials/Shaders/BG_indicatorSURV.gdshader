shader_type canvas_item;

// Background fade parameters
uniform float fade_start : hint_range(0.0, 1.0) = 0.3;  // Where fade begins
uniform float fade_end : hint_range(0.0, 1.0) = 0.8;    // Where fade ends (fully transparent)
uniform vec4 base_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);  // Base color (black by default)
uniform int fade_direction : hint_range(0, 3) = 0;  // 0=Right, 1=Left, 2=Up, 3=Down

// Corner rounding (only on the solid color side)
uniform float corner_radius : hint_range(0.0, 0.5) = 0.1;  // Corner roundness

// Optional curve adjustment
uniform float fade_curve : hint_range(0.1, 4.0) = 1.0;  // 1.0 = linear, >1.0 = curved

// Rounded rectangle function
float rounded_rect(vec2 uv, vec2 size, float radius) {
	vec2 d = abs(uv - 0.5) - size * 0.5 + radius;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - radius;
}

void fragment() {
	vec2 uv = UV;
	float fade_progress = 0.0;

	// Calculate fade progress based on direction
	if (fade_direction == 0) {
		// Fade to RIGHT (black on left, transparent on right)
		fade_progress = uv.x;
	} else if (fade_direction == 1) {
		// Fade to LEFT (black on right, transparent on left)
		fade_progress = 1.0 - uv.x;
	} else if (fade_direction == 2) {
		// Fade to UP (black on bottom, transparent on top)
		fade_progress = 1.0 - uv.y;
	} else {
		// Fade to DOWN (black on top, transparent on bottom)
		fade_progress = uv.y;
	}

	// Apply fade curve
	fade_progress = pow(fade_progress, fade_curve);

	// Calculate alpha based on fade range
	float fade_alpha = 1.0;
	if (fade_progress > fade_start) {
		if (fade_progress < fade_end) {
			// We're in the fade zone
			float fade_zone_progress = (fade_progress - fade_start) / (fade_end - fade_start);
			fade_alpha = 1.0 - smoothstep(0.0, 1.0, fade_zone_progress);
		} else {
			// Fully transparent
			fade_alpha = 0.0;
		}
	}

	// Apply corner rounding only on the solid color side
	float corner_alpha = 1.0;
	if (corner_radius > 0.0) {
		vec2 corner_uv = uv;
		vec2 rect_size = vec2(1.0, 1.0);

		// Adjust the rounded rectangle based on fade direction
		if (fade_direction == 0) {
			// Fade to RIGHT - round left corners only
			rect_size.x = fade_end; // Only apply rounding to the solid part
			corner_uv.x = uv.x / fade_end; // Scale UV for the solid area
			if (uv.x > fade_end) corner_alpha = 1.0; // No rounding in transparent area
			else {
				float corner_dist = rounded_rect(corner_uv, rect_size, corner_radius);
				corner_alpha = 1.0 - smoothstep(-0.01, 0.01, corner_dist);
			}
		} else if (fade_direction == 1) {
			// Fade to LEFT - round right corners only
			rect_size.x = fade_end;
			corner_uv.x = (1.0 - uv.x) / fade_end;
			if ((1.0 - uv.x) > fade_end) corner_alpha = 1.0;
			else {
				float corner_dist = rounded_rect(corner_uv, rect_size, corner_radius);
				corner_alpha = 1.0 - smoothstep(-0.01, 0.01, corner_dist);
			}
		} else if (fade_direction == 2) {
			// Fade to UP - round bottom corners only
			rect_size.y = fade_end;
			corner_uv.y = uv.y / fade_end;
			if (uv.y > fade_end) corner_alpha = 1.0;
			else {
				float corner_dist = rounded_rect(corner_uv, rect_size, corner_radius);
				corner_alpha = 1.0 - smoothstep(-0.01, 0.01, corner_dist);
			}
		} else {
			// Fade to DOWN - round top corners only
			rect_size.y = fade_end;
			corner_uv.y = (1.0 - uv.y) / fade_end;
			if ((1.0 - uv.y) > fade_end) corner_alpha = 1.0;
			else {
				float corner_dist = rounded_rect(corner_uv, rect_size, corner_radius);
				corner_alpha = 1.0 - smoothstep(-0.01, 0.01, corner_dist);
			}
		}
	}

	// Combine fade alpha with corner alpha
	float final_alpha = fade_alpha * corner_alpha;

	// Set final color
	COLOR = vec4(base_color.rgb, base_color.a * final_alpha);
}
