shader_type spatial;
render_mode cull_disabled;
// Backpack canvas (#260): the shell takes the shape of what is inside it. Each item is a box proxy
// in pack space; a vertex inside one (plus the lining) is pushed out along its normal. An emptier
// pack slumps: the top drops and the walls cave in a little. Back faces show the lining.
// Look: worn grey canvas with a stitched leather base, paler on rubbed edges, grimier low down,
// creased where slack and pale where stretched, painterly like the world, lit in soft bands (NPR).

#include "res://shaders/environment/materials/painterly_surface.gdshaderinc"

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
// Side pocket only: cloth over the body's wall at pocket_wall_x (signed: its side). Empty, it falls
// flat against the wall; holding something (item 0), it wraps it this tightly (1 skin-tight).
uniform bool is_pocket = false;
uniform float pocket_wall_x = 0.17;
uniform float pocket_wrap = 0.85;
uniform float pocket_flat_m = 0.006;
// Empty pocket: its outer layer spreads this share of its depth off the inner one (the fold).
uniform float pocket_fold_spread = 0.03;
// The body under the pockets: a box (half size, its centre at (0, half.y, half.z)) rounded by
// body_round; the pocket is sewn onto that surface as it slumps, not onto a flat wall.
uniform vec3 body_half = vec3(0.17, 0.26, 0.11);
uniform float body_round = 0.06;
// Sleeves: a pocket holds up to two items, split by a divider at sleeve_split_z (0: one sleeve;
// cloth with z under the split belongs to sleeve 1). Each item is an upright elliptic cylinder
// (round_half: half size along x and z, 0 = none) round round_axis (x, z): the cloth shrink-wraps
// it, not its box. While one is pushed in, cloth below its item_bottom is still the empty pouch;
// the hem (top hem_band_m under rim_y) opens hem_open_m past it and friction drags it down.
uniform float sleeve_split_z = 0.0;
uniform vec2 round_half[2];
uniform vec2 round_axis[2];
uniform float item_bottom[2];
uniform float seat_bottom[2];
uniform float hem_open_m[2];
uniform float hem_drag_m[2];
uniform float rim_y = 0.17;
uniform float hem_band_m = 0.02;
uniform float hem_drag_fall_m = 0.08;
uniform float funnel_m = 0.035;
// Creases where the cloth is slack: depth (m) and spacing (per metre).
uniform float fold_m = 0.004;
uniform float fold_freq = 70.0;
// Front panel only: a leather maker's patch, UV rect (u0, v0, u1, v1); zero area draws none.
uniform vec4 patch_rect = vec4(0.0);
uniform vec3 patch_colour : source_color = vec3(0.42, 0.28, 0.17);
// The world's painterly breakup, scaled from metres down to the pack.
uniform float painterly_scale = 22.0;

varying vec2 v_zip;
varying vec3 v_pack;
varying vec3 v_pack_normal;
varying float v_edge;
varying float v_crease;
varying float v_stretch;

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

// |x| of the body's side surface at (y, z): the rounded box, caved in as the shell slumps empty.
float body_side_x(float y, float z) {
	float dy = max(abs(y - body_half.y) - (body_half.y - body_round), 0.0);
	float dz = max(abs(z - body_half.z) - (body_half.z - body_round), 0.0);
	float x = body_half.x - body_round + sqrt(max(body_round * body_round - dy * dy - dz * dz, 0.0));
	return x - slump_wall_m * (1.0 - clamp(fill, 0.0, 1.0)) * smoothstep(0.1, 0.4, y / pack_height_m);
}

// The empty pocket: its inner layer sewn on the body, the outer one on it, the mouth closed and
// the rim drooping.
vec3 pocket_flat(vec3 p, vec3 n, float side, float out_x) {
	vec3 target = p;
	target.y -= 0.012 * smoothstep(0.1, 0.17, p.y);
	target.x = side * (body_side_x(target.y, p.z) + (n.x * side < -0.5 ? 0.0 : pocket_flat_m + out_x * pocket_fold_spread));
	return target;
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
	v_pack_normal = n;
	v_stretch = 0.0;
	float slack = empty * high;
	// Pocket cloth wrapped onto a cylinder takes the cylinder's normal, or it would light as a box.
	vec3 out_n = n;
	if (is_pocket) {
		float side = sign(pocket_wall_x);
		float out_x = (p.x - pocket_wall_x) * side;
		int k = sleeve_split_z > 0.0 && p.z < sleeve_split_z ? 1 : 0;
		if (round_half[k].x > 0.0) {
			// Shrink-wrap onto the ellipse (radial projection plus the lining); under its bottom, a disc.
			vec2 d = p.xz - round_axis[k];
			float dl = length(d);
			vec2 dir = dl > 0.0001 ? d / dl : vec2(side, 0.0);
			float hem = smoothstep(rim_y - hem_band_m, rim_y, p.y);
			vec2 e = max(round_half[k] + vec2(lining_m + hem_open_m[k] * hem), round_half[k] + vec2(0.001));
			float r = 1.0 / length(dir / e);
			vec3 hug = p;
			hug.xz = round_axis[k] + dir * (p.y < item_bottom[k] - lining_m * 0.5 ? min(dl, r) : r);
			float dragged = smoothstep(rim_y - hem_drag_fall_m, rim_y, p.y);
			hug.y -= hem_drag_m[k] * dragged;
			if (n.x * side < -0.5) {
				hug.x = side * body_side_x(p.y, p.z);
			}
			float empty_w = smoothstep(0.0, funnel_m, item_bottom[k] - p.y) * smoothstep(0.0, 0.01, item_bottom[k] - seat_bottom[k]);
			vec3 target = mix(hug, pocket_flat(p, n, side, out_x), empty_w);
			v_stretch = clamp(length(target - p) / 0.03, 0.0, 1.0) * (1.0 - empty_w);
			bool sewn = n.x * side < -0.5 || p.y < item_bottom[k] - lining_m * 0.5;
			out_n = normalize(mix(sewn ? n : normalize(vec3(dir.x / (e.x * e.x), 0.0, dir.y / (e.y * e.y))), n, empty_w));
			shaped = target - p;
			// Taut over the item; the hem's drag bunches the cloth under it; the empty part hangs slack.
			float bunch = clamp(hem_drag_m[k] / 0.008, 0.0, 1.0) * dragged * (1.0 - hem);
			slack = mix(0.08 + 0.9 * bunch, 1.0, empty_w);
		} else if (sleeve_split_z <= 0.0 && item_count > 0) {
			// Wrapped round what it holds: pulled onto the item's box, the wall side kept on the wall.
			vec3 c = item_centre[0].xyz;
			vec3 h = item_half[0].xyz + vec3(lining_m);
			vec3 q = clamp(p, c - h, c + h);
			vec3 d = p - q;
			bool inside = length(d) < 0.0001;
			vec3 target;
			if (inside) {
				// Cloth inside the item goes all the way out along its normal to the item's face:
				// what a pocket holds never shows through it.
				vec3 safe_n = vec3(abs(n.x) > 0.001 ? n.x : 0.001, abs(n.y) > 0.001 ? n.y : 0.001, abs(n.z) > 0.001 ? n.z : 0.001);
				vec3 exits = (c + sign(safe_n) * h - p) / safe_n;
				target = p + n * (min(exits.x, min(exits.y, exits.z)) + 0.002);
			} else {
				target = q + normalize(d) * 0.002;
			}
			if (n.x * side < -0.5) {
				target.x = side * body_side_x(p.y, p.z);
			}
			v_stretch = clamp(length(target - p) / 0.03, 0.0, 1.0);
			shaped = (target - p) * (inside ? 1.0 : pocket_wrap);
			slack = 1.0 - pocket_wrap;
		} else {
			// Empty: the outer layer falls onto the wall and closes the mouth; the rim droops.
			shaped = pocket_flat(p, n, side, out_x) - p;
			slack = 1.0;
		}
	}
	// Slack cloth creases: soft ridges and valleys across it, broken up so they never line up.
	float crease = sin(dot(p, vec3(0.15, 1.0, 0.35)) * fold_freq + noise3(p * 25.0) * 5.0);
	shaped += n * crease * fold_m * slack;
	v_crease = crease * slack;
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
	if (is_pocket) {
		NORMAL = normalize(mat3(inverse(to_pack)) * out_n);
	}
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

// The maker's patch: stitched leather with a pressed ring round a peak, in the panel's UV rect.
vec3 _patch(vec3 colour, vec2 uv) {
	vec2 size = patch_rect.zw - patch_rect.xy;
	vec2 local = (uv - patch_rect.xy) / size;
	if (local.x < 0.0 || local.x > 1.0 || local.y < 0.0 || local.y > 1.0) {
		return colour;
	}
	vec3 leather = patch_colour * (0.85 + 0.3 * noise3(vec3(uv * 60.0, 1.0)));
	// The panel's UV runs up its height (x) and across its width (y): measure in metres.
	vec2 size_m = size * vec2(pack_height_m, 0.34);
	float border = min(min(local.x, 1.0 - local.x) * size_m.x, min(local.y, 1.0 - local.y) * size_m.y);
	float stitch = (1.0 - smoothstep(0.004, 0.007, abs(border - 0.012))) * step(0.5, fract((local.x + local.y) * 22.0));
	leather = mix(leather, stitch_colour, stitch);
	vec2 m = (local - 0.5) * vec2(size_m.x / size_m.y, 1.0) * 2.0;
	float ring = 1.0 - smoothstep(0.03, 0.06, abs(length(m) - 0.55));
	float peak = step(abs(m.y), 0.35 - m.x * 0.8) * step(-0.35, m.x) * step(m.x, 0.4);
	leather *= 1.0 - 0.35 * max(ring, peak * 0.8);
	return leather;
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
		if (is_panel && patch_rect.z > patch_rect.x) {
			colour = _patch(colour, UV);
		}
		vec3 rubbed = mix(colour, vec3(dot(colour, vec3(0.333))), 0.35) * 1.35 + 0.03;
		colour = mix(colour, rubbed, v_edge * edge_wear);
		colour *= 1.0 - grime * (1.0 - smoothstep(0.03, 0.3, v_pack.y));
		// Creases darken in their valleys; stretched cloth goes paler and smoother.
		colour *= 1.0 - 0.22 * smoothstep(0.15, 1.0, -v_crease) + 0.06 * smoothstep(0.3, 1.0, v_crease);
		colour *= 1.0 + 0.12 * v_stretch;
		colour = hfn_painterly_surface_color(colour, v_pack * painterly_scale, v_pack_normal, 1.0);
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
