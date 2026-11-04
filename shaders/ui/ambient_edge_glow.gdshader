shader_type canvas_item;
render_mode unshaded;

// One color at a time. Each 1.2-second phase lights both long horizontal edges,
// then fades to black before the next color. No five-color spatial mixing.
uniform float clock_seconds = 0.0;
uniform float intensity : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform vec4 yellow : source_color = vec4(1.0, 0.73, 0.17, 1.0);
uniform vec4 warm_white : source_color = vec4(0.86, 0.87, 0.84, 1.0);
uniform vec4 red : source_color = vec4(0.95, 0.22, 0.17, 1.0);
uniform vec4 green : source_color = vec4(0.16, 0.77, 0.47, 1.0);
uniform vec4 blue : source_color = vec4(0.26, 0.49, 1.0, 1.0);

const float PHASE_SECONDS = 1.2;
const float CYCLE_SECONDS = 6.0;

vec3 color_for_phase(int phase) {
    if (phase == 0) {
        return yellow.rgb;
    }
    if (phase == 1) {
        return warm_white.rgb;
    }
    if (phase == 2) {
        return red.rgb;
    }
    if (phase == 3) {
        return green.rgb;
    }
    return blue.rgb;
}

float edge_falloff(float distance) {
    // A broad, soft light spill that reaches zero well before screen center.
    float haze = exp(-pow(distance / 0.17, 1.7));
    return haze * (1.0 - smoothstep(0.29, 0.41, distance));
}

float longitudinal_wave(float x, float center) {
    float d = (x - center) / 0.28;
    return 0.58 + 0.42 * exp(-d * d);
}

void fragment() {
    vec2 uv = UV;
    float cycle_time = mod(max(clock_seconds, 0.0), CYCLE_SECONDS);
    int active_phase = min(4, int(floor(cycle_time / PHASE_SECONDS)));
    float phase_time = fract(cycle_time / PHASE_SECONDS);

    // No crossfade between hues: the old color has faded out before index changes.
    float fade_in = smoothstep(0.02, 0.27, phase_time);
    float fade_out = 1.0 - smoothstep(0.73, 0.98, phase_time);
    float pulse = fade_in * fade_out;

    // Both top and bottom follow the same active hue, with independent ripples.
    float upper_wobble = 0.017 * sin(uv.x * 8.7 + cycle_time * 1.7);
    float lower_wobble = 0.020 * sin(uv.x * 7.3 - cycle_time * 1.5 + 1.1);
    float top_distance = max(0.0, uv.y + upper_wobble);
    float bottom_distance = max(0.0, 1.0 - uv.y + lower_wobble);

    // Highlight slowly traverses each long edge in opposite directions.
    float sweep = smoothstep(0.05, 0.95, phase_time);
    float top_center = mix(-0.15, 1.15, sweep);
    float bottom_center = mix(1.15, -0.15, sweep);
    float top_glow = edge_falloff(top_distance) * longitudinal_wave(uv.x, top_center);
    float bottom_glow = edge_falloff(bottom_distance) * longitudinal_wave(uv.x, bottom_center);

    float brightness = max(top_glow, bottom_glow) * pulse * intensity * 0.83;
    // Pure black, including the center: never a permanent colored base layer.
    COLOR = vec4(color_for_phase(active_phase) * brightness, 1.0);
}
