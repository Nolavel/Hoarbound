shader_type canvas_item;

// === 3D PERSPECTIVE UNIFORMS ===
uniform float fov : hint_range(1.0, 179.0) = 90.0;
uniform bool cull_back = true;
uniform float y_rot : hint_range(-180.0, 180.0) = 0.0;
uniform float x_rot : hint_range(-180.0, 180.0) = 0.0;
uniform float inset : hint_range(0.0, 1.0) = 0.0;
uniform bool use_rect_size = false;
uniform vec2 rect_size = vec2(100.0, 100.0);

// === CONTROL UNIFORMS ===
uniform bool enable_3d_effect = true;

// === TRANSPARENCY CONTROL ===
uniform float alpha_factor : hint_range(0.0, 1.0) = 1.0; // 0 = полностью прозрачный, 1 = полностью непрозрачный

varying vec2 o;
varying vec3 p;

void vertex() {
	if (enable_3d_effect) {
		// === 3D PERSPECTIVE VERTEX PROCESSING ===
		float y_rad = y_rot * PI / 180.0;
		float x_rad = x_rot * PI / 180.0;

		float sin_b = sin(y_rad);
		float cos_b = cos(y_rad);
		float sin_c = sin(x_rad);
		float cos_c = cos(x_rad);

		mat3 inv_rot_mat = mat3(
			vec3(cos_b, 0.0, -sin_b),
			vec3(sin_b * sin_c, cos_c, cos_b * sin_c),
			vec3(sin_b * cos_c, -sin_c, cos_b * cos_c)
		);

		float t = tan(fov * PI / 360.0);
		p = inv_rot_mat * vec3((UV - 0.5), 0.5 / t);
		float v = (0.5 / t) + 0.5;
		p.xy *= v * inv_rot_mat[2].z;
		o = v * inv_rot_mat[2].xy;

		if (use_rect_size) {
			VERTEX += (UV - 0.5) * rect_size * t * (1.0 - inset);
		} else {
			VERTEX += (UV - 0.5) / TEXTURE_PIXEL_SIZE * t * (1.0 - inset);
		}
	} else {
		// === STANDARD VERTEX PROCESSING ===
		o = vec2(0.0);
		p = vec3(UV - 0.5, 1.0);
	}
}

void fragment() {
	vec2 final_uv = UV;

	if (enable_3d_effect) {
		// === 3D PERSPECTIVE FRAGMENT PROCESSING ===
		if (cull_back && p.z <= 0.0) {
			discard;
		}

		vec2 perspective_uv = (p.xy / p.z) - o;

		if (abs(perspective_uv.x) > 0.5 || abs(perspective_uv.y) > 0.5) {
			discard;
		}

		final_uv = perspective_uv + 0.5;
	}

	// Получаем цвет текстуры
	vec4 tex_color = texture(TEXTURE, final_uv);

	// Прозрачность формы
	tex_color.a *= alpha_factor;

	COLOR = tex_color;
}
