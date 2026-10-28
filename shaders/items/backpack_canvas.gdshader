shader_type spatial;
render_mode cull_disabled;
// Backpack canvas (#260): the shell takes the shape of what is inside it. Each item is a box proxy
// in pack space; a vertex inside one (plus the lining) is pushed out along its normal. An emptier
// pack slumps: the top drops and the walls cave in a little. Back faces show the lining.

const int MAX_ITEMS = 16;

uniform vec3 canvas_colour : source_color = vec3(0.36, 0.33, 0.22);
uniform vec3 lining_colour : source_color = vec3(0.16, 0.16, 0.15);
uniform float roughness_value = 0.9;
// Pack-space transform of this mesh (identity for the shell, the hinge pose for the front panel).
uniform mat4 to_pack = mat4(1.0);
uniform vec4 item_centre[MAX_ITEMS];
uniform vec4 item_half[MAX_ITEMS];
uniform int item_count = 0;
// Canvas and lining between an item and the outer face, metres; the bulge feathers over `soft_m`.
uniform float lining_m = 0.012;
uniform float soft_m = 0.03;
// Canvas does not balloon: it gives this much at most, and whatever is bigger shows through the top.
uniform float max_stretch_m = 0.02;
// 0 empty .. 1 full; the empty slump's depth at the top and on the walls, metres.
uniform float fill = 1.0;
uniform float slump_top_m = 0.07;
uniform float slump_wall_m = 0.018;
uniform float pack_height_m = 0.52;
// Free edge of the front panel droops this far toward gravity (model-space direction).
uniform float droop_m = 0.0;
uniform vec3 droop_dir = vec3(0.0, -1.0, 0.0);
uniform float panel_length_m = 0.0;
// Mesh pocket on the panel's inside: UV rect (x0, y0, x1, y1); zero area draws none.
uniform vec4 mesh_pocket = vec4(0.0);

varying float v_lining;

float box_distance(vec3 p, vec3 c, vec3 h) {
	vec3 q = abs(p - c) - h;
	return length(max(q, vec3(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

void vertex() {
	vec3 p = (to_pack * vec4(VERTEX, 1.0)).xyz;
	vec3 n = normalize(mat3(to_pack) * NORMAL);
	float push = 0.0;
	for (int i = 0; i < MAX_ITEMS; i++) {
		if (i >= item_count) {
			break;
		}
		float d = box_distance(p, item_centre[i].xyz, item_half[i].xyz) - lining_m;
		push = max(push, smoothstep(soft_m, -soft_m, d) * max(soft_m - d, 0.0));
	}
	push = min(push, max_stretch_m);
	float empty = 1.0 - clamp(fill, 0.0, 1.0);
	float high = smoothstep(pack_height_m * 0.45, pack_height_m, p.y);
	vec3 slump = vec3(0.0, -slump_top_m * high, 0.0) - n * slump_wall_m * smoothstep(0.1, 0.4, p.y / pack_height_m);
	vec3 shaped = n * push + slump * empty;
	VERTEX += mat3(inverse(to_pack)) * shaped;
	if (panel_length_m > 0.0) {
		float t = clamp(VERTEX.y / panel_length_m, 0.0, 1.0);
		VERTEX += droop_dir * droop_m * t * t;
	}
}

void fragment() {
	vec3 colour = FRONT_FACING ? canvas_colour : lining_colour;
	if (!FRONT_FACING && mesh_pocket.z > mesh_pocket.x) {
		vec2 inside = step(mesh_pocket.xy, UV) * step(UV, mesh_pocket.zw);
		if (inside.x * inside.y > 0.5) {
			vec2 g = abs(fract(UV * 90.0) - 0.5);
			float hole = step(0.18, min(g.x, g.y));
			colour = mix(vec3(0.07), lining_colour * 1.25, hole);
		}
	}
	// Weathered canvas: a faint cross weave and darker grime toward the bottom.
	vec2 weave = abs(fract(UV * vec2(160.0, 160.0)) - 0.5);
	colour *= 0.94 + 0.06 * step(0.25, min(weave.x, weave.y));
	ALBEDO = colour;
	ROUGHNESS = roughness_value;
}
