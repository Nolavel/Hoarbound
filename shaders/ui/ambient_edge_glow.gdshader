shader_type canvas_item;
render_mode unshaded;

uniform float clock_seconds = 2.0;
uniform float intensity : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform vec4 yellow : source_color = vec4(1.0, 0.73, 0.17, 1.0);
uniform vec4 warm_white : source_color = vec4(0.86, 0.87, 0.84, 1.0);
uniform vec4 red : source_color = vec4(0.95, 0.22, 0.17, 1.0);
uniform vec4 green : source_color = vec4(0.16, 0.77, 0.47, 1.0);
uniform vec4 blue : source_color = vec4(0.26, 0.49, 1.0, 1.0);

float plume(float x, float center, float width) {
    float offset = (x - center) / width;
    return exp(-offset * offset);
}

vec3 palette_color(int index) {
    if (index == 0) {
        return yellow.rgb;
    }
    if (index == 1) {
        return warm_white.rgb;
    }
    if (index == 2) {
        return red.rgb;
    }
    if (index == 3) {
        return green.rgb;
    }
    return blue.rgb;
}

void fragment() {
    vec2 uv = UV;
    float time = clock_seconds;

    // Independent, slowly deforming top and bottom glow fronts.
    float upper_curve = 0.031 * sin(uv.x * 6.7 + time * 0.69)
        + 0.014 * sin(uv.x * 12.4 - time * 0.29);
    float lower_curve = 0.039 * sin(uv.x * 5.1 - time * 0.59 + 1.4)
        + 0.010 * sin(uv.x * 15.1 + time * 0.38);
    float upper_distance = max(0.0, uv.y + 0.008 + upper_curve);
    float lower_distance = max(0.0, 1.0 - uv.y + 0.016 + lower_curve);
    float upper = exp(-pow(upper_distance / 0.24, 2.0));
    float lower = exp(-pow(lower_distance / 0.27, 2.0));

    // Overlapping color clouds, not five hard stripes.
    vec3 total_color = vec3(0.0);
    float total_weight = 0.0;
    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float center = 0.08 + fi * 0.215
            + 0.070 * sin(time * 0.53 + fi * 1.37);
        float weight = plume(uv.x, center, 0.145);
        total_color += palette_color(i) * weight;
        total_weight += weight;
    }
    vec3 hue = total_color / max(total_weight, 0.0001);

    float breathing = 0.85 + 0.15 * sin(time * 1.34 + uv.x * 2.8);
    float entrance = smoothstep(0.0, 0.68, time);
    float exit_fade = 1.0 - smoothstep(5.25, 6.0, time);
    float envelope = entrance * exit_fade;
    float edge_light = (upper * 0.88 + lower * 0.92) * breathing
        * envelope * intensity;
    vec3 charcoal = vec3(0.022, 0.026, 0.033);
    vec3 glow = hue * edge_light * 1.75;
    COLOR = vec4(charcoal + glow, 1.0);
}
