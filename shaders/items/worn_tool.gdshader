shader_type spatial;
// Worn hand tools (#260, Build-Rite refs): a base colour broken into blocky painted cells (the refs'
// chunky brushwork) with two wear colours; metal rusts in patches, plastic and rubber get grimy and
// rubbed pale on edges. One material per slot; the cell size is in metres of the tool's own space.

uniform vec3 base_colour : source_color = vec3(0.5, 0.5, 0.52);
// Wear: patch colour A (rust orange / grime), B (dark rust / dirt), and how much of each shows.
uniform vec3 wear_a : source_color = vec3(0.45, 0.22, 0.1);
uniform vec3 wear_b : source_color = vec3(0.18, 0.1, 0.06);
uniform float amount_a = 0.45;
uniform float amount_b = 0.25;
// Rubbed edges go toward this colour (bare steel, faded plastic).
uniform vec3 rub_colour : source_color = vec3(0.7, 0.68, 0.64);
uniform float rub = 0.3;
uniform float cell_m = 0.004;
uniform float metallic_base = 0.0;
uniform float metallic_wear = 0.0;
uniform float roughness_base = 0.6;
uniform float roughness_wear = 0.85;

varying vec3 v_local;
varying vec3 v_normal;
#include "res://shaders/environment/materials/garment_frost.gdshaderinc"
varying vec3 v_frost_pos;
varying vec3 v_frost_normal;

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

void vertex() {
	v_local = VERTEX;
	v_normal = NORMAL;
	v_frost_pos = VERTEX;
	v_frost_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Blocky cells: the patch field is sampled at each cell's centre, so wear comes in painted squares.
	vec3 cell = floor(v_local / cell_m);
	vec3 centre = (cell + 0.5) * cell_m;
	float field_a = noise3(centre * 55.0) * 0.7 + noise3(centre * 160.0) * 0.3;
	float field_b = noise3(centre * 90.0 + 13.0) * 0.6 + noise3(centre * 240.0 + 5.0) * 0.4;
	float jitter = hash3(cell) * 0.12;
	float a = step(1.0 - amount_a, field_a + jitter - 0.06);
	float b = step(1.0 - amount_b, field_b + jitter - 0.06);
	vec3 colour = base_colour * (0.9 + 0.2 * hash3(cell + 3.0));
	colour = mix(colour, wear_a * (0.85 + 0.3 * hash3(cell + 7.0)), a);
	colour = mix(colour, wear_b * (0.85 + 0.3 * hash3(cell + 11.0)), b);
	// Edges, where the face normal leans between axes, rub toward the bare colour.
	vec3 an = abs(normalize(v_normal));
	float edge = smoothstep(0.1, 0.3, 1.0 - max(an.x, max(an.y, an.z)));
	float rubbed = step(0.55, hash3(cell + 17.0)) * edge * rub;
	colour = mix(colour, rub_colour, rubbed);
	float worn = max(a, b);
	float metal_out = mix(metallic_base, metallic_wear, worn) + rubbed * 0.4;
	float rough_out = mix(roughness_base, roughness_wear, worn) - rubbed * 0.2;
	hfn_apply_garment_frost(colour, rough_out, metal_out, v_frost_pos, v_frost_normal, 1.0);
	ALBEDO = colour;
	METALLIC = metal_out;
	ROUGHNESS = rough_out;
}
