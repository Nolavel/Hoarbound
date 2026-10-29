shader_type spatial;
render_mode cull_back, depth_draw_opaque;
// Production fixed-world tile geometry: identical 2m source-ground triangles
// and settled snow basis to SnowChunkCover; only footprint delta is tile-local.
#include "res://shaders/environment/snow/snow_surface.gdshaderinc"
#include "res://shaders/environment/stylized_shadow.gdshaderinc"
#include "res://shaders/environment/materials/painterly_surface.gdshaderinc"

uniform sampler2D deformation : filter_linear, repeat_disable;
uniform vec2 tile_origin = vec2(0.0);
uniform float tile_m = 3.2;
uniform bool debug_height = false;
uniform float reference_y = 0.0;
uniform vec3 fresh_color : source_color = vec3(0.8, 0.83, 0.88);
uniform vec3 packed_color : source_color = vec3(0.5, 0.56, 0.68);
uniform sampler2D wind_tex : filter_linear, repeat_disable;
uniform vec2 wind_origin = vec2(0.0);
uniform vec2 wind_extent = vec2(0.0);
uniform float wind_max = 2.5;
varying vec3 v_world;
varying float v_press;
varying float v_rim;
varying float v_city;
varying float v_shore;

float city_at(vec2 xz) {
    if (wind_extent.x <= 0.0) { return 1.0; }
    vec2 uv = (xz - wind_origin) / wind_extent;
    if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) { return 1.0; }
    vec4 w = texture(wind_tex, uv);
    return mix(w.r, w.g, snow_storm_share) * wind_max;
}
float tile_detail(vec2 xz) {
    return 1.0 - smoothstep(12.0, 17.0, distance(xz, snow_player_xz));
}

void vertex() {
    vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    vec2 uv = clamp((world.xz - tile_origin) / tile_m, vec2(0.0), vec2(1.0));
    // 33 endpoints for 32 cells: texel centre at both shared world edges.
    uv = uv * (32.0 / 33.0) + vec2(0.5 / 33.0);
    vec4 stamp = texture(deformation, uv);
    v_press = max(stamp.r, 0.0);
    v_rim = max(stamp.g, 0.0);
    v_shore = UV.y;
    v_city = city_at(world.xz) * v_shore;
    // Interpolated from the *same* 2m chunk vertices, not freshly sampled
    // at higher-detail points. Prevents baseline pops as the LOD changes.
    VERTEX.y += snow_settled_depth * mix(UV2.x, UV2.y, snow_storm_share) + v_rim - v_press;
    v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    // Complementary dither to the chunk-cover material. Never clip tile edges
    // to the camera-centred square; the transition is radial in WORLD space.
    if (snow_trail_dither(v_world.xz) >= tile_detail(v_world.xz)) { discard; }
    float depth = snow_base_depth(v_world.xz, v_city);
    if (depth < 0.012) { discard; }
    HFN_SHADOW_FRAGMENT(v_world);
    vec3 geo = normalize(cross(dFdy(v_world), dFdx(v_world)));
    if (geo.y < 0.0) { geo = -geo; }
    vec3 n = snow_outer_normal(geo, v_world.xz, v_city);
    float press = smoothstep(0.007, 0.12, v_press);
    float bank = smoothstep(0.006, 0.04, v_rim);
    n = normalize(n + vec3((snow_noise(v_world.xz * 28.0)-0.5)*press*0.15,
        0.0, (snow_noise(v_world.xz * 28.0 + 10.0)-0.5)*press*0.15));
    NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
    vec3 color = hfn_painterly_surface_color(
        snow_outer_albedo(fresh_color, v_world, depth, v_city), v_world, n, 0.38);
    ALBEDO = mix(color, packed_color, press * 0.72);
    ALBEDO *= 1.0 + bank * 0.055;
    ROUGHNESS = mix(0.85, 0.72, press);
    if (debug_height) {
        ALBEDO = vec3(0.0);
        EMISSION = vec3(clamp(0.5 + (v_world.y - reference_y) * 0.08, 0.0, 1.0), 0.32, 0.90);
        ROUGHNESS = 1.0;
    }
}
void light() {
    float ndotl = max(dot(NORMAL, LIGHT), 0.0);
    DIFFUSE_LIGHT += ndotl * hfn_stylized_shadow(ATTENUATION, LIGHT_IS_DIRECTIONAL) * LIGHT_COLOR / PI;
}
