// Stylized shadows on stock Godot (docs/technical/STYLIZED_SHADOWS.md): fragment() calls
// HFN_SHADOW_FRAGMENT(world_pos); light() multiplies N.L by hfn_stylized_shadow().

global uniform float stylized_shadow_strength;
// Brush-stroke mask for the spray (tools/art/generate_shadow_brush_masks.py); mix 0 keeps
// the value noise, 1 uses the mask.
global uniform sampler2D stylized_shadow_brush_mask : filter_linear_mipmap, repeat_enable;
global uniform float stylized_shadow_brush_mix;

// Lookup offset: amplitude in metres and base frequency in cycles per metre.
const float HFN_SHADOW_OFFSET_M = 0.18;
const float HFN_SHADOW_OFFSET_FREQ = 3.0;
// Spray: base frequency and cut shift; half the jitter stays below both margins.
const float HFN_SHADOW_SPRAY_FREQ = 9.0;
const float HFN_SHADOW_SPRAY_JITTER = 0.6;
const float HFN_SHADOW_SPRAY_CONTRAST = 2.5;
// One mask tile covers this many metres; contrast maps mask 0..1 onto the spray.
const float HFN_SHADOW_BRUSH_TILE_M = 1.5;
const float HFN_SHADOW_BRUSH_CONTRAST = 1.4;
// Three tones of the directional shadow term: core 0, mid, lit 1.
const float HFN_SHADOW_CUT_LOW = 0.34;
const float HFN_SHADOW_CUT_HIGH = 0.66;
const float HFN_SHADOW_MID_TONE = 0.45;

varying float hfn_shadow_spray;


// PCG3D integer hash (Jarzynski & Olano 2020, "Hash Functions for GPU Rendering").
vec3 hfn_shadow_hash3(vec3 cell) {
	uvec3 v = uvec3(ivec3(cell));
	v = v * 1664525u + 1013904223u;
	v.x += v.y * v.z;
	v.y += v.z * v.x;
	v.z += v.x * v.y;
	v ^= v >> 16u;
	v.x += v.y * v.z;
	v.y += v.z * v.x;
	v.z += v.x * v.y;
	return vec3(v) * (1.0 / 4294967295.0);
}


// Vector value noise in [-1, 1] per channel.
vec3 hfn_shadow_noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	vec3 a = mix(hfn_shadow_hash3(i), hfn_shadow_hash3(i + vec3(1.0, 0.0, 0.0)), u.x);
	vec3 b = mix(hfn_shadow_hash3(i + vec3(0.0, 1.0, 0.0)), hfn_shadow_hash3(i + vec3(1.0, 1.0, 0.0)), u.x);
	vec3 c = mix(hfn_shadow_hash3(i + vec3(0.0, 0.0, 1.0)), hfn_shadow_hash3(i + vec3(1.0, 0.0, 1.0)), u.x);
	vec3 d = mix(hfn_shadow_hash3(i + vec3(0.0, 1.0, 1.0)), hfn_shadow_hash3(i + vec3(1.0, 1.0, 1.0)), u.x);
	return mix(mix(a, b, u.y), mix(c, d, u.y), u.z) * 2.0 - 1.0;
}


// Three-octave fbm; octaves finer than ~3 px fade out (pixel_m: metres per pixel).
vec3 hfn_shadow_fbm3(vec3 world_pos, float freq, float pixel_m) {
	vec3 sum = vec3(0.0);
	float amp = 0.5;
	for (int octave = 0; octave < 3; octave++) {
		float keep = 1.0 - smoothstep(0.2, 0.45, freq * pixel_m);
		sum += hfn_shadow_noise3(world_pos * freq + float(octave) * 19.7) * amp * keep;
		freq *= 2.0;
		amp *= 0.55;
	}
	return sum / 0.926;
}


// Brush mask on the three world planes, faded like the spray's base octave: mip
// averages keep the unpainted gaps, so they never settle to 0.5 on their own.
float hfn_shadow_brush(vec3 noise_pos, vec3 n, float pixel_m) {
	vec3 w = n * n;
	w *= w;
	w /= max(w.x + w.y + w.z, 1e-5);
	vec3 p = noise_pos / HFN_SHADOW_BRUSH_TILE_M;
	float m = texture(stylized_shadow_brush_mask, p.xz).r * w.y
		+ texture(stylized_shadow_brush_mask, p.zy).r * w.x
		+ texture(stylized_shadow_brush_mask, p.xy).r * w.z;
	float keep = 1.0 - smoothstep(0.2, 0.45, HFN_SHADOW_SPRAY_FREQ * pixel_m);
	return clamp((m - 0.5) * 2.0 * HFN_SHADOW_BRUSH_CONTRAST, -1.0, 1.0) * keep;
}


// View-space LIGHT_VERTEX offset in the surface plane; also returns the spray.
// noise_pos is metric and fixed to the surface: world for static meshes, model for movers.
vec4 hfn_shadow_prepare(vec3 noise_pos, vec3 view_normal, mat4 inv_view, mat4 view, float offset_scale) {
	float strength = clamp(stylized_shadow_strength, 0.0, 1.0);
	float pixel_m = max(length(fwidth(noise_pos)), 1e-5);
	vec3 n = normalize((inv_view * vec4(view_normal, 0.0)).xyz);
	vec3 noise = hfn_shadow_fbm3(noise_pos, HFN_SHADOW_OFFSET_FREQ, pixel_m);
	vec3 tangent = noise - n * dot(noise, n);
	vec3 offset = (view * vec4(tangent * HFN_SHADOW_OFFSET_M * offset_scale * strength, 0.0)).xyz;
	float brush_mix = clamp(stylized_shadow_brush_mix, 0.0, 1.0);
	float spray = 0.0;
	if (brush_mix < 1.0) {
		spray = hfn_shadow_fbm3(noise_pos + vec3(41.3, -7.9, 23.1), HFN_SHADOW_SPRAY_FREQ, pixel_m).x;
		spray = clamp(spray * HFN_SHADOW_SPRAY_CONTRAST, -1.0, 1.0);
	}
	if (brush_mix > 0.0) {
		spray = mix(spray, hfn_shadow_brush(noise_pos, n, pixel_m), brush_mix);
	}
	return vec4(offset, spray);
}


#define HFN_SHADOW_FRAGMENT_SCALED(noise_pos, offset_scale) vec4 hfn_prep = hfn_shadow_prepare(noise_pos, NORMAL, INV_VIEW_MATRIX, VIEW_MATRIX, offset_scale); LIGHT_VERTEX = VERTEX + hfn_prep.xyz; hfn_shadow_spray = hfn_prep.w
#define HFN_SHADOW_FRAGMENT(world_pos) HFN_SHADOW_FRAGMENT_SCALED(world_pos, 1.0)


// Directional ATTENUATION is the shadow alone; local lights also carry distance
// falloff, so they keep only the torn lookup.
float hfn_stylized_shadow(float attenuation, bool directional) {
	float base = clamp(attenuation, 0.0, 1.0);
	float strength = clamp(stylized_shadow_strength, 0.0, 1.0);
	if (!directional || strength <= 0.0) {
		return base;
	}
	float v = base + hfn_shadow_spray * 0.5 * HFN_SHADOW_SPRAY_JITTER;
	float tone = mix(step(HFN_SHADOW_CUT_LOW, v) * HFN_SHADOW_MID_TONE, 1.0, step(HFN_SHADOW_CUT_HIGH, v));
	return mix(base, tone, strength);
}
