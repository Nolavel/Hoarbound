shader_type canvas_item;
render_mode unshaded;


// ============================================================================
// COLOR
// ============================================================================

uniform vec4 base_color : source_color = vec4(0.42, 0.42, 0.42, 0.82);


// ============================================================================
// MAIN GRADIENT
// ============================================================================

// Где начинается обычный fade.
uniform float fade_start : hint_range(0.0, 1.0) = 0.12;

// Где он становится полностью прозрачным.
uniform float fade_end : hint_range(0.0, 1.0) = 0.96;

// 0 = fade вправо
// 1 = fade влево
// 2 = fade вверх
// 3 = fade вниз
uniform int fade_direction : hint_range(0, 3) = 0;

// Форма fade.
uniform float fade_curve : hint_range(0.1, 4.0) = 1.35;


// ============================================================================
// APPEAR / REVEAL
// ============================================================================

// 0 = полностью скрыто
// 1 = полностью раскрыто
//
// Именно этот параметр анимирует QuickAccessUI.
uniform float reveal : hint_range(0.0, 1.0) = 1.0;

// Насколько мягкий движущийся прозрачный край во время появления.
//
// Больше значение = более длинный, мягкий хвост.
uniform float reveal_softness : hint_range(0.001, 0.5) = 0.16;

// Кривая раскрытия.
//
// < 1.0 быстрее начинает раскрываться,
// > 1.0 медленнее начинает и ускоряется к концу.
uniform float reveal_curve : hint_range(0.1, 4.0) = 0.75;


// ============================================================================
// SHAPE
// ============================================================================

uniform float corner_radius : hint_range(0.0, 0.5) = 0.08;


// ============================================================================
// HELPERS
// ============================================================================

float rounded_rect(
	vec2 uv,
	vec2 size,
	float radius
) {
	vec2 d = abs(uv - 0.5) - size * 0.5 + radius;

	return length(max(d, 0.0))
		+ min(max(d.x, d.y), 0.0)
		- radius;
}


float get_fade_progress(vec2 uv) {
	if (fade_direction == 0) {
		// Solid слева -> transparent справа.
		return uv.x;
	}

	if (fade_direction == 1) {
		// Solid справа -> transparent слева.
		return 1.0 - uv.x;
	}

	if (fade_direction == 2) {
		// Solid снизу -> transparent сверху.
		return 1.0 - uv.y;
	}

	// Solid сверху -> transparent снизу.
	return uv.y;
}


// ============================================================================
// FRAGMENT
// ============================================================================

void fragment() {
	vec2 uv = UV;


	// --------------------------------------------------------------------
	// DIRECTIONAL PROGRESS
	// --------------------------------------------------------------------

	float progress = get_fade_progress(uv);

	progress = pow(
		clamp(progress, 0.0, 1.0),
		fade_curve
	);


	// --------------------------------------------------------------------
	// PERMANENT BACKGROUND GRADIENT
	// --------------------------------------------------------------------

	float safe_range = max(
		fade_end - fade_start,
		0.0001
	);

	float gradient_t = clamp(
		(progress - fade_start) / safe_range,
		0.0,
		1.0
	);

	float gradient_alpha = 1.0 - smoothstep(
		0.0,
		1.0,
		gradient_t
	);


	// --------------------------------------------------------------------
	// REVEAL
	//
	// Reveal не просто меняет opacity всей плашки.
	//
	// Он двигает прозрачную границу от solid side к transparent side.
	// Поэтому плашка визуально "растягивается".
	// --------------------------------------------------------------------

	float reveal_value = pow(
		clamp(reveal, 0.0, 1.0),
		reveal_curve
	);

	// При reveal = 0 край находится перед началом прямоугольника.
	// При reveal = 1 край выходит немного за его пределы.
	float reveal_edge = mix(
		-reveal_softness,
		1.0 + reveal_softness,
		reveal_value
	);

	float reveal_alpha = 1.0 - smoothstep(
		reveal_edge - reveal_softness,
		reveal_edge,
		progress
	);


	// --------------------------------------------------------------------
	// ROUNDED RECT
	// --------------------------------------------------------------------

	float corner_alpha = 1.0;

	if (corner_radius > 0.0) {
		float corner_distance = rounded_rect(
			uv,
			vec2(1.0),
			corner_radius
		);

		corner_alpha = 1.0 - smoothstep(
			-0.01,
			0.01,
			corner_distance
		);
	}


	// --------------------------------------------------------------------
	// FINAL
	// --------------------------------------------------------------------

	float final_alpha =
		base_color.a
		* gradient_alpha
		* reveal_alpha
		* corner_alpha;


	COLOR = vec4(
		base_color.rgb,
		final_alpha
	);
}
