shader_type spatial;
render_mode cull_disabled;
// Backpack canvas (#260): the shell takes the shape of what is inside it. Each item is a box proxy
// in pack space; a vertex inside one (plus the lining) is pushed out along its normal. An emptier
// pack slumps: the top drops and the walls cave in a little. Back faces show the lining.
// Look: worn grey canvas with a stitched leather base, paler on rubbed edges, grimier low down,
// lit in soft bands (NPR) like the rest of the stylised world.

const int MAX_ITEMS = 16;

uniform vec3 canvas_colour : source_color = vec3(0.30, 0.32, 0.34);
// Leather base: up to this height in pack space, its colour, and the stitch line along its top.
uniform bool leather_on = true;
uniform float leather_top_m = 0.085;
uniform vec3 leather_colour : source_color = vec3(0.36, 0.23, 0.14);
uniform vec3 stitch_colour : source_color = vec3(0.62, 0.56, 0.44);
// Wear: rubbed edges go paler, the canvas is mottled, the low part grimier.
uniform float edge_wear = 0.55;
uniform float mottle = 0.09;
uniform float grime = 0.18;
// NPR light: the lit side breaks into this many soft bands.
uniform float light_bands = 3.0;
uniform float band_softness = 0.08;
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
// Mesh pocket on the panel's inside: UV rect (x0, y0, x1, y1); zero area draws none.
uniform vec4 mesh_pocket = vec4(0.0);
// Zipper along the panel's top and sides. UV2 carries (distance to the seam, path from top centre), m.
uniform bool zipper_on = false;
uniform float zipper_half_m = 0.016;
uniform float tooth_pitch_m = 0.006;
uniform vec3 tape_colour : source_color = vec3(0.025, 0.025, 0.03);
uniform vec3 tooth_colour : source_color = vec3(0.32, 0.32, 0.34);
// How far each slider has run down its side; the canvas parts only behind it.
uniform float zip_s = 0.0;
// Panel only: the part above the bend line (pack-space y, z) turns out by bend_angle; a slider
// still on the top edge just lifts the mouth between the two sliders by mouth_m.
uniform bool is_panel = false;
uniform float bend_y = 1.0;
uniform float bend_z = 0.2;
uniform float bend_angle = 0.0;
uniform float mouth_m = 0.0;
uniform float top_y = 0.52;
// Panel only: where the zip is still open its edge stands off the shell this far, closed folded or not.
uniform float gap_m = 0.015;
// Shell only: the walls next to the open part of the seam give outward this far.
uniform float side_give_m = 0.0;

varying vec2 v_zip;
varying vec3 v_pack;
varying float v_edge;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float box_distance(vec3 p, vec3 c, vec3 h) {
	vec3 q = abs(p - c) - h;
	return length(max(q, vec3(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

void vertex() {
	vec3 p = (to_pack * vec4(VERTEX, 1.0)).xyz;
	vec3 n = normalize(mat3(to_pack) * NORMAL);
	v_pack = p;
	// On a rounded edge the normal leans between two axes: that is where canvas rubs pale.
	vec3 an = abs(n);
	v_edge = smoothstep(0.08, 0.26, 1.0 - max(an.x, max(an.y, an.z)));
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
	v_zip = UV2;
	if (zipper_on) {
		// Open behind the sliders only: the run from the top centre they have already passed.
		float open_part = smoothstep(zip_s, zip_s - 0.04, UV2.y);
		if (is_panel) {
			shaped += n * gap_m * open_part * (1.0 - smoothstep(0.0, 0.06, UV2.x));
		} else {
			shaped += n * side_give_m * open_part * (1.0 - smoothstep(0.0, 0.09, UV2.x));
		}
	}
	VERTEX += mat3(inverse(to_pack)) * shaped;
	if (is_panel) {
		float mouth = mouth_m * smoothstep(top_y - 0.1, top_y, VERTEX.y) * smoothstep(zip_s, zip_s - 0.04, UV2.y);
		VERTEX += vec3(0.0, -0.3, 1.0) * mouth;
		// Fold out round the bend line; a short ramp makes the crease cloth, not a hinge.
		float rel_y = VERTEX.y - bend_y;
		if (rel_y > 0.0) {
			float a = bend_angle * smoothstep(0.0, 0.035, rel_y);
			float rel_z = VERTEX.z - bend_z;
			VERTEX.y = bend_y + rel_y * cos(a) - rel_z * sin(a);
			VERTEX.z = bend_z + rel_y * sin(a) + rel_z * cos(a);
			NORMAL = vec3(NORMAL.x, NORMAL.y * cos(a) - NORMAL.z * sin(a), NORMAL.y * sin(a) + NORMAL.z * cos(a));
			float t = clamp(rel_y / max(top_y - bend_y, 0.05), 0.0, 1.0);
			VERTEX += droop_dir * droop_m * t * t;
		}
	}
}

void fragment() {
	vec3 colour = FRONT_FACING ? canvas_colour : lining_colour;
	float metal = 0.0;
	if (zipper_on && v_zip.x < zipper_half_m) {
		// Black tape; the teeth are a lighter interlocking row along the seam.
		colour = tape_colour;
		float row = step(v_zip.x, zipper_half_m * 0.5);
		float tooth = step(0.5, fract(v_zip.y / tooth_pitch_m + (is_panel ? 0.5 : 0.0)));
		colour = mix(colour, tooth_colour, row * tooth);
		metal = row * tooth;
	}
	if (!FRONT_FACING && mesh_pocket.z > mesh_pocket.x) {
		vec2 inside = step(mesh_pocket.xy, UV) * step(UV, mesh_pocket.zw);
		if (inside.x * inside.y > 0.5) {
			vec2 g = abs(fract(UV * 90.0) - 0.5);
			float hole = step(0.18, min(g.x, g.y));
			colour = mix(vec3(0.07), lining_colour * 1.25, hole);
		}
	}
	// Weathered canvas: a faint cross weave, mottling, pale rubbed edges, grime low down.
	vec2 weave = abs(fract(UV * vec2(160.0, 160.0)) - 0.5);
	colour *= 0.94 + 0.06 * step(0.25, min(weave.x, weave.y));
	if (FRONT_FACING) {
		float blotch = noise3(v_pack * 18.0) * 0.65 + noise3(v_pack * 55.0) * 0.35;
		colour *= 1.0 + (blotch - 0.5) * 2.0 * mottle;
		if (leather_on && v_pack.y < leather_top_m) {
			float hide = noise3(v_pack * 30.0);
			colour = leather_colour * (0.85 + 0.3 * hide);
			// A row of stitches just under the seam.
			float row = 1.0 - smoothstep(0.0015, 0.003, abs(v_pack.y - (leather_top_m - 0.008)));
			float dash = step(0.5, fract((v_pack.x + v_pack.z) * 120.0));
			colour = mix(colour, stitch_colour, row * dash);
		}
		vec3 rubbed = mix(colour, vec3(dot(colour, vec3(0.333))), 0.35) * 1.35 + 0.03;
		colour = mix(colour, rubbed, v_edge * edge_wear);
		colour *= 1.0 - grime * (1.0 - smoothstep(0.03, 0.3, v_pack.y));
	}
	ALBEDO = colour;
	METALLIC = metal * 0.6;
	ROUGHNESS = mix(roughness_value, 0.45, metal);
}

void light() {
	// Soft bands instead of a smooth ramp; shadow is folded in before banding.
	float lit = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	float stepped = 0.0;
	for (float b = 1.0; b <= light_bands; b += 1.0) {
		float edge = (b - 0.5) / light_bands;
		stepped += smoothstep(edge - band_softness, edge + band_softness, lit) / light_bands;
	}
	DIFFUSE_LIGHT += LIGHT_COLOR * stepped / PI;
}
