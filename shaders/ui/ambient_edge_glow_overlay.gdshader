shader_type canvas_item;
render_mode unshaded;

// Gemini-like soft elliptical light caps, not a horizontal strip or noise texture.
// One cap opens inward from each screen edge. Center and side corners stay clear.
uniform vec4 glow_color : source_color = vec4(0.76, 0.77, 0.75, 1.0);
uniform float glow_strength : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float edge_width : hint_range(0.025, 0.25, 0.005) = 0.100;
uniform float clock_seconds = 0.0;
uniform float motion_factor : hint_range(0.0, 1.0, 0.01) = 1.0;

float cap(vec2 p, float center, float depth, float half_width) {
    // Elliptical distance to a center just outside the visible frame.
    // The inward-facing contour is a soft arc: tallest at x=center.
    vec2 q = vec2((p.x - center) / half_width, (p.y + 0.018) / depth);
    float r = length(q);
    float halo = exp(-3.0 * r * r) * (1.0 - smoothstep(0.77, 1.15, r));
    return halo;
}

void fragment() {
    float t = clock_seconds;
    float breath = 1.0 + motion_factor * 0.035 * sin(t * 1.2);
    float depth = edge_width * 1.65 * breath;
    float top = cap(UV, 0.48 + motion_factor * 0.025 * sin(t * 0.5), depth, 0.43);
    float bottom = cap(vec2(UV.x, 1.0 - UV.y), 0.52 - motion_factor * 0.025 * sin(t * 0.5), depth, 0.43);
    COLOR = vec4(glow_color.rgb, clamp(max(top, bottom) * glow_strength * glow_color.a, 0.0, 0.82));
}
