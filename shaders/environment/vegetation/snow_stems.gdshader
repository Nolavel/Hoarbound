// Dead shrub stems that stay poking out of the snow: each clump rides up with the drawn snow
// top, keeping bury_m of it under the surface. Reads snow state, never writes it.
shader_type spatial;
render_mode diffuse_lambert;

global uniform sampler2D snow_field : filter_linear, repeat_disable;
global uniform vec4 snow_window;
global uniform float snow_settled_depth;
// How deep a clump's root stays under the snow top (the rest of the clump shows).
uniform float bury_m = 0.3;

// Snow top at xz: the live shell field inside its window (eased over the outer 6 m, as the
// shell draws it), the chunk-wide settled depth outside.
float stem_snow_top(vec2 xz, float ground) {
	float settled = ground + snow_settled_depth;
	if (snow_window.w < 0.5) {
		return settled;
	}
	vec2 uv = (xz - snow_window.xy) / snow_window.z;
	if (uv.x <= 0.0 || uv.y <= 0.0 || uv.x >= 1.0 || uv.y >= 1.0) {
		return settled;
	}
	vec2 to_edge = min(uv, 1.0 - uv) * snow_window.z;
	float edge = smoothstep(0.0, 6.0, min(to_edge.x, to_edge.y));
	return mix(settled, texture(snow_field, uv).r, edge);
}

vec3 stem_lift(vec3 vertex, mat4 model) {
	vec3 root = model[3].xyz;
	float lift = max(stem_snow_top(root.xz, root.y) - bury_m - root.y, 0.0);
	return vertex + inverse(mat3(model)) * vec3(0.0, lift, 0.0);
}

#define HFN_STATIC_WORLD
#define HFN_VERTEX_EXTRA VERTEX = stem_lift(VERTEX, MODEL_MATRIX);
#include "res://shaders/environment/materials/stylized_environment_body.gdshaderinc"
