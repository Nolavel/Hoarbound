shader_type canvas_item;
render_mode blend_disabled;

// Deformation-state v2 shaping. Geometry shaping operates on compression only;
// displaced powder bypasses the old common blur. B/A travel with the state.
// R: compression below settled top. G: displaced heap above settled top.
// B: broken crust / disturbance. A: compacted density.
uniform sampler2D source : filter_nearest, repeat_disable;
// Settled field: B below 0.5 is softness scaled by 0.49, above is cut away.
uniform sampler2D field : filter_linear, repeat_disable;
uniform int pass = 0;
// Metres a compression wall drops per texel of run: tan(slope) * texel size.
uniform float drop_powder = 0.021;
uniform float drop_crust = 0.14;
// Farthest a wall reaches, in texels.
uniform int reach = 24;

void fragment() {
	vec2 texel = 1.0 / vec2(textureSize(source, 0));
	vec4 state = texture(source, UV);
	vec4 shaped = state;
	float b = texture(field, UV).b;
	float powder = b < 0.5 ? smoothstep(0.45, 0.95, b / 0.49) : 0.0;

	if (pass < 2) {
		float drop = mix(drop_crust, drop_powder, powder);
		vec2 axis = pass == 0 ? vec2(texel.x, 0.0) : vec2(0.0, texel.y);
		for (int i = 1; i <= reach; i++) {
			float fall = drop * float(i);
			if (fall > 1.2) {
				break;
			}
			vec4 plus_state = texture(source, UV + axis * float(i));
			float plus_compression = plus_state.r - fall;
			if (plus_compression > shaped.r) {
				shaped.r = plus_compression;
				shaped.b = max(shaped.b, plus_state.b * 0.88);
				shaped.a = max(shaped.a, plus_state.a * 0.82);
			}
			vec4 minus_state = texture(source, UV - axis * float(i));
			float minus_compression = minus_state.r - fall;
			if (minus_compression > shaped.r) {
				shaped.r = minus_compression;
				shaped.b = max(shaped.b, minus_state.b * 0.88);
				shaped.a = max(shaped.a, minus_state.a * 0.82);
			}
		}
	} else {
		// Flatten only the interior of a compacted floor. Neighbours across a strong
		// depth edge are rejected, and broken crust further suppresses filtering.
		float centre = state.r;
		float edge_limit = mix(0.005, 0.018, powder);
		float weighted = centre * 5.0;
		float weight_sum = 5.0;
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				if (x == 0 && y == 0) {
					continue;
				}
				vec4 neighbour_state = texture(source, UV + vec2(float(x), float(y)) * texel);
				float neighbour = neighbour_state.r;
				float same_floor = 1.0 - smoothstep(edge_limit, edge_limit * 1.8, abs(neighbour - centre));
				float similar_density = 1.0 - smoothstep(0.25, 0.65, abs(neighbour_state.a - state.a));
				float spatial = (x == 0 || y == 0) ? 1.0 : 0.62;
				float w = same_floor * similar_density * spatial;
				weighted += neighbour * w;
				weight_sum += w;
			}
		}
		float flat_floor = weighted / max(weight_sum, 0.001);
		float flatten = mix(0.05, 0.52, clamp(state.a, 0.0, 1.0));
		flatten *= 1.0 - clamp(state.b, 0.0, 1.0) * 0.72;
		shaped.r = mix(centre, flat_floor, flatten);
	}

	shaped.r = max(shaped.r, 0.0);
	shaped.g = max(state.g, 0.0);
	shaped.b = clamp(shaped.b, 0.0, 1.0);
	shaped.a = clamp(shaped.a, 0.0, 1.0);
	COLOR = shaped;
}
