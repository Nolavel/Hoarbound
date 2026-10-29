shader_type spatial;
// Carabiner (#260): steel under red paint worn through in chips; the screw sleeve is knurled.

uniform vec3 paint_colour : source_color = vec3(0.6, 0.11, 0.08);
uniform vec3 steel_colour : source_color = vec3(0.52, 0.52, 0.54);
uniform vec3 grime_colour : source_color = vec3(0.2, 0.19, 0.18);
// Share of the paint left, 0..1; the sleeve keeps more of it.
uniform float paint_left = 0.5;
uniform bool knurled = false;
// World-size of a paint chip, metres.
uniform float chip_m = 0.006;

varying vec3 v_local;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	vec3 p = v_local / chip_m;
	float chips = noise(p) * 0.65 + noise(p * 2.7) * 0.35;
	float paint = step(1.0 - paint_left, chips);
	float grime = noise(p * 0.6 + 7.0);
	vec3 metal = mix(steel_colour, grime_colour, grime * 0.6);
	vec3 colour = mix(metal, paint_colour * (0.8 + 0.3 * grime), paint);
	float metallic = mix(0.85, 0.0, paint);
	float rough = mix(0.38, 0.7, paint);
	if (knurled) {
		// Diamond knurl: two crossing helices darken the grooves.
		vec2 uv = UV * vec2(24.0, 6.0);
		float a = abs(fract(uv.x + uv.y) - 0.5);
		float b = abs(fract(uv.x - uv.y) - 0.5);
		float groove = 1.0 - smoothstep(0.05, 0.14, min(a, b));
		colour *= 1.0 - groove * 0.55;
		rough = mix(rough, 0.85, groove);
	}
	ALBEDO = colour;
	METALLIC = metallic;
	ROUGHNESS = rough;
}
