shader_type canvas_item;
render_mode unshaded;

// Full-screen Hub signal. Uneven diagonal tongues of light grow IN from
// the top/bottom edge; the middle of the screen is never tinted.
uniform vec4 glow_color : source_color = vec4(0.76, 0.77, 0.75, 1.0);
uniform float glow_strength : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float edge_width : hint_range(0.025, 0.25, 0.005) = 0.115;
uniform float clock_seconds = 0.0;
uniform float motion_factor : hint_range(0.0, 1.0, 0.01) = 1.0;

float hash2(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise2(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x),
               mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Separate seeds and slants make the two screen edges asymmetrical.
// Sampling along x + slant * distance lets the longer lobes lean diagonally,
// rather than tracing a single horizontal horizon.
float irregular_edge(float x, float distance, float seed, float slant, float t) {
    float drift = t * 0.095 * motion_factor;
    float along = x + slant * distance;
    float coarse = noise2(vec2(along * 7.3 + seed + drift, seed * 0.61 + distance * 2.0));
    float medium = noise2(vec2(along * 19.0 - seed * 0.7 - drift * 0.7, seed + distance * 11.0));
    float fine = noise2(vec2(along * 43.0 + seed * 2.3, distance * 33.0 + seed));

    // Thin base close to the edge, with sparse deeper protrusions.
    // Both length and luminance vary along the edge.
    float lobes = smoothstep(0.36, 0.78, coarse);
    float serration = 0.70 + 0.30 * medium;
    float depth = edge_width * (0.18 + 0.87 * lobes * serration);
    float contour = distance / max(depth, 0.005);
    float body = exp(-pow(contour, 1.45)) * (1.0 - smoothstep(0.95, 1.65, contour));
    float patch = 0.16 + 0.84 * smoothstep(0.22, 0.78, coarse * 0.76 + medium * 0.24);
    float texture = mix(0.72, 1.0, fine);
    return body * patch * texture;
}

void fragment() {
    float t = clock_seconds;
    float top = irregular_edge(UV.x, UV.y, 13.7, 1.85, t);
    float bottom = irregular_edge(UV.x, 1.0 - UV.y, 47.2, -2.25, t * 0.91);
    float edge = max(top, bottom);
    COLOR = vec4(glow_color.rgb, clamp(edge * glow_strength * glow_color.a, 0.0, 0.9));
}
