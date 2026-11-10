shader_type canvas_item;
render_mode unshaded;

// Full viewport action feedback for the open Hub. Not a card material.
uniform vec4 glow_color : source_color = vec4(0.76, 0.77, 0.75, 1.0);
uniform float glow_strength : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float edge_width : hint_range(0.025, 0.25, 0.005) = 0.115;
uniform float clock_seconds = 0.0;
uniform float motion_factor : hint_range(0.0, 1.0, 0.01) = 1.0;

float edge_falloff(float distance) {
    float d = distance / max(edge_width, 0.01);
    return exp(-pow(d, 1.65)) * (1.0 - smoothstep(1.4, 2.2, d));
}

float wave(float x, float center) {
    float d = (x - center) / 0.36;
    return 0.67 + 0.33 * exp(-d * d);
}

void fragment() {
    float t = clock_seconds;
    float top_distance = max(0.0, UV.y + motion_factor * 0.009 * sin(UV.x * 9.0 + t));
    float bottom_distance = max(0.0, 1.0 - UV.y + motion_factor * 0.012 * sin(UV.x * 8.0 - t * 0.9));
    float top_center = 0.5 + motion_factor * 0.48 * sin(t * 0.6);
    float bottom_center = 0.5 - motion_factor * 0.48 * sin(t * 0.5);
    float edge = max(edge_falloff(top_distance) * wave(UV.x, top_center),
                     edge_falloff(bottom_distance) * wave(UV.x, bottom_center));
    // Straight alpha. Only top and bottom; the whole middle is untouched.
    COLOR = vec4(glow_color.rgb, clamp(edge * glow_strength * glow_color.a, 0.0, 0.9));
}
