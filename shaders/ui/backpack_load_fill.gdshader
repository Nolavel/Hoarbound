shader_type canvas_item;
render_mode unshaded;

// Load fraction is independent from BG_frame's reveal animation.
uniform float fill_fraction : hint_range(0.0, 1.0) = 0.0;
uniform vec4 fill_color : source_color = vec4(0.70, 0.70, 0.63, 0.94);

void fragment() {
	float coverage = 1.0 - smoothstep(fill_fraction - 0.012, fill_fraction + 0.012, UV.x);
	coverage *= step(0.0001, fill_fraction);
	// Same soft rightward falloff language as BG_frame, at smaller scale.
	float trailing_fade = 1.0 - smoothstep(0.77, 1.0, UV.x) * 0.25;
	COLOR = vec4(fill_color.rgb, fill_color.a * coverage * trailing_fade);
}
