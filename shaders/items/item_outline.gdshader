// Outline of an item in the open pack (inverted hull): hover is a pale rim, a held item a warm one, an item
// that does not fit a red one. Drawn as a material overlay, so the item's own look is untouched.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, shadows_disabled;

uniform vec4 rim_colour : source_color = vec4(1.0, 1.0, 1.0, 0.9);
// Rim width in world metres, whatever the mesh node's scale.
uniform float width_m = 0.004;

void vertex() {
	float scale = max(length(MODEL_MATRIX[0].xyz), 0.0001);
	VERTEX += NORMAL * width_m / scale;
}

void fragment() {
	ALBEDO = rim_colour.rgb;
	ALPHA = rim_colour.a;
}
