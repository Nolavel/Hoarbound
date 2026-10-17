shader_type canvas_item;
render_mode blend_disabled;

// Shapes compression into walls the snow can hold. Displaced powder is a
// separate positive channel and deliberately bypasses the old common blur.
// Pass 0/1 build the compression slope cone; pass 2 performs a small edge-aware
// relaxation so compacted floors keep a firm silhouette instead of turning to gel.
// R: compression below settled top. G: displaced heap above settled top.
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
	vec2 state = texture(source, UV).rg;
	float out_compression = state.r;
	float displaced = state.g;
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
			out_compression = max(out_compression, texture(source, UV + axis * float(i)).r - fall);
			out_compression = max(out_compression, texture(source, UV - axis * float(i)).r - fall);
		}
	} else {
		// Only neighbours on the same side of a strong depth edge contribute.
		// Loose powder relaxes a little more; crust stays almost unfiltered.
		float centre = state.r;
		float edge_limit = mix(0.006, 0.025, powder);
		float weighted = centre * 4.0;
		float weight_sum = 4.0;
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				if (x == 0 && y == 0) {
					continue;
				}
				float neighbour = texture(source, UV + vec2(float(x), float(y)) * texel).r;
				float same_surface = 1.0 - smoothstep(edge_limit, edge_limit * 2.0, abs(neighbour - centre));
				float spatial = (x == 0 || y == 0) ? 1.0 : 0.65;
				float w = same_surface * spatial;
				weighted += neighbour * w;
				weight_sum += w;
			}
		}
		float filtered = weighted / max(weight_sum, 0.001);
		out_compression = mix(centre, filtered, mix(0.04, 0.18, powder));
	}
	COLOR = vec4(max(out_compression, 0.0), max(displaced, 0.0), 0.0, 1.0);
}
