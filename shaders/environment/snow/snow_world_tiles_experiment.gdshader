shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// EXPERIMENT ONLY. No SnowShell or retained-window sampling.
// Vertex Y = baked world terrain/snow baseline + world-tile immutable-lattice deformation.
uniform sampler2D deformation : filter_linear, repeat_disable;
uniform vec2 tile_origin = vec2(0.0);
uniform float tile_m = 3.2;
uniform bool debug_height = false;
uniform float reference_y = 0.0;
varying vec3 world_snow;
varying float compression;
varying float displaced;

void vertex() {
    vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    // Tile texture stores the 33 vertex samples incl. shared boundaries.
    // The +0.5 / 33 offset makes actual mesh vertices land on texel CENTRES.
    vec2 uv = (world.xz - tile_origin) / tile_m;
    uv = clamp(uv, vec2(0.0), vec2(1.0)) * (32.0 / 33.0) + vec2(0.5 / 33.0);
    vec4 state = texture(deformation, uv);
    compression = state.r;
    displaced = state.g;
    VERTEX.y += state.g - state.r;
    world_snow = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec3 geo = normalize(cross(dFdy(world_snow), dFdx(world_snow)));
    if (geo.y < 0.0) { geo = -geo; }
    NORMAL = normalize((VIEW_MATRIX * vec4(geo, 0.0)).xyz);
    float pressed = smoothstep(0.008, 0.105, compression);
    float rim = smoothstep(0.003, 0.04, displaced);
    float grain = fract(sin(dot(floor(world_snow.xz * 23.0), vec2(127.1, 311.7))) * 43758.5453);
    vec3 fresh = vec3(0.78, 0.83, 0.89) * (0.97 + grain * 0.035);
    vec3 compact = vec3(0.48, 0.57, 0.70);
    ALBEDO = mix(fresh, compact, pressed * 0.75) * (1.0 + rim * 0.10);
    ROUGHNESS = mix(0.9, 0.78, pressed);
    if (debug_height) {
        // Surface identifier: G/B constant; RED encodes post-displacement Y.
        ALBEDO = vec3(0.0);
        EMISSION = vec3(clamp(0.5 + (world_snow.y - reference_y) * 0.08, 0.0, 1.0), 0.32, 0.90);
        ROUGHNESS = 1.0;
    }
}
