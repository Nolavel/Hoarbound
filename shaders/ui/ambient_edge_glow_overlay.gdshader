shader_type canvas_item;
render_mode unshaded;

// Transparent, local overlay for a single UI card. The original opaque
// ambient_edge_glow.gdshader is preserved as the five-color reference.
uniform vec4 glow_color : source_color = vec4(0.88, 0.86, 0.81, 1.0);
uniform float glow_strength : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float edge_width : hint_range(0.04, 0.30, 0.01) = 0.15;
uniform float clock_seconds = 0.0;
uniform float motion_factor : hint_range(0.0, 1.0, 0.01) = 1.0;

float edge_falloff(float distance, float width) {
    float d = distance / max(width, 0.01);
    return exp(-pow(d, 1.7)) * (1.0 - smoothstep(1.65, 2.4, d));
}

float edge_wave(float x, float center) {
    float d = (x - center) / 0.29;
    return 0.58 + 0.42 * exp(-d * d);
}

void fragment() {
    // UV is local to THIS card, not SCREEN_UV or the gameplay viewport.
    float t = clock_seconds;
    float top_y = max(0.0, UV.y + motion_factor * 0.012 * sin(UV.x * 8.7 + t * 1.3));
    float bottom_y = max(0.0, 1.0 - UV.y + motion_factor * 0.015 * sin(UV.x * 7.3 - t * 1.1 + 1.1));
    float top_center = mix(0.5, 0.5 + 0.65 * sin(t * 0.55), motion_factor);
    float bottom_center = mix(0.5, 0.5 - 0.65 * sin(t * 0.48), motion_factor);
    float top = edge_falloff(top_y, edge_width) * edge_wave(UV.x, top_center);
    float bottom = edge_falloff(bottom_y, edge_width) * edge_wave(UV.x, bottom_center);
    float alpha = clamp(max(top, bottom) * glow_strength * glow_color.a, 0.0, 0.85);

    // Crucial difference from the reference shader: no opaque black fill.
    // The center reaches alpha = 0, preserving icons/text/background.
    COLOR = vec4(glow_color.rgb, alpha);
}
