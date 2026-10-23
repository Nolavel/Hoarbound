shader_type canvas_item;

// Frost over one body region of the HUD silhouette: it creeps from the extremity tip
// (fingertips, toes, crown) inward as `amount` rises. y0/y1 bound the region in UV.

uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 frost : source_color = vec4(0.48, 0.74, 1.0, 0.95);
uniform float y0 = 0.0;
uniform float y1 = 1.0;
uniform float tip_at_top = 0.0;

void fragment() {
	float m = texture(TEXTURE, UV).a;
	float t = clamp((UV.y - y0) / max(y1 - y0, 0.001), 0.0, 1.0);
	t = mix(t, 1.0 - t, tip_at_top);
	float cover = smoothstep(1.0 - amount - 0.18, 1.0 - amount + 0.18, t) * step(0.01, amount);
	COLOR = vec4(frost.rgb, frost.a * m * cover * (0.4 + 0.6 * amount));
}
