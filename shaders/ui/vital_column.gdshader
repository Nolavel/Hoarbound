shader_type canvas_item;

// One vital column: dense at the bottom, fading upward, rounded bottom corners.
// The pigment layer cuts at `fill` from the top down and may draw a thin edge line.

uniform vec2 size = vec2(36.0, 112.0);
uniform float radius = 8.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform float fill : hint_range(0.0, 1.0) = 1.0;
uniform float fade_start : hint_range(0.0, 1.0) = 0.0;
uniform float fade_end : hint_range(0.0, 2.0) = 1.05;
uniform float edge_line : hint_range(0.0, 1.0) = 0.0;

// Signed inside distance in pixels; only the bottom corners are rounded.
float inside_round_bottom(vec2 p) {
	vec2 q = vec2(min(p.x, size.x - p.x), size.y - p.y);
	if (q.x < radius && q.y < radius) {
		return radius - length(vec2(radius) - q);
	}
	return min(q.x, q.y);
}

void fragment() {
	vec2 p = UV * size;
	float inside = clamp(inside_round_bottom(p) + 0.5, 0.0, 1.0);
	float h = 1.0 - UV.y;
	float fade = 1.0 - smoothstep(fade_start, fade_end, h);
	float clip = 1.0 - smoothstep(fill - 0.02, fill, h);
	float line = edge_line * (1.0 - smoothstep(0.4, 1.4, abs(h - fill) * size.y)) * step(0.02, fill) * 0.9;
	COLOR = vec4(tint.rgb, tint.a * max(fade * clip, line) * inside);
}
