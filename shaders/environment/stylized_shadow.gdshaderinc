// Stylized shadows on stock Godot (docs/technical/STYLIZED_SHADOWS.md): fragment() calls
// HFN_SHADOW_FRAGMENT(world_pos); light() multiplies N.L by hfn_stylized_shadow().

global uniform float stylized_shadow_strength;
// Experimental style witness. Both are 0 in project.godot; the capture harness alone toggles them.
global uniform float stylized_shadow_mass_strength;
global uniform float stylized_shadow_edge_strength;
// Set by ShelterShadowBinder from ThermalManager.sheltered_changed; never a weather/lighting override.
// 0 = outdoor production lookup, 1 = stronger torn indoor local-light silhouettes.
global uniform float stylized_shadow_interior_mode;
// Brush-stroke mask for the spray (tools/art/generate_shadow_brush_masks.py); mix 0 keeps
// the value noise, 1 uses the mask. Experimental capture mode uses values > 1.5 to select
// the painted-edge path without changing the production ProjectSettings contract.
global uniform sampler2D stylized_shadow_brush_mask : filter_linear_mipmap, repeat_enable;
global uniform float stylized_shadow_brush_mix;

// Production lookup offset: amplitude in metres and base frequency in cycles per metre.
const float HFN_SHADOW_OFFSET_M = 0.18;
const float HFN_SHADOW_OFFSET_FREQ = 3.0;
// The previously improvised 0.40 m/8 Hz indoor mode was not the old shader.
// Historical edge and warp implementations are below, gated to interiors.
// Painted-edge experiment: one coarse displacement layer, smaller than production FBM.
const float HFN_PAINTED_OFFSET_M = 0.095;
const float HFN_PAINTED_OFFSET_FREQ = 2.35;
const float HFN_PAINTED_EDGE_SHIFT = 0.14;
const float HFN_PAINTED_EDGE_AMOUNT = 0.92;
// Second painted-edge pass: metre-scale, sparse breakup. This is deliberately much coarser
// than the dry-brush texture so it reads as authored pigment islands, not procedural grain.
const float HFN_PAINTED_BLOB_FREQ = 0.62;
const float HFN_PAINTED_STROKE_TONE = 0.40;
const float HFN_PAINTED_ISLAND_TONE = 0.58;
// Spray: base frequency and cut shift; half the jitter stays below both margins.
const float HFN_SHADOW_SPRAY_FREQ = 9.0;
const float HFN_SHADOW_SPRAY_JITTER = 0.6;
const float HFN_SHADOW_SPRAY_CONTRAST = 2.5;
// One mask tile covers this many metres; contrast maps mask 0..1 onto the spray.
const float HFN_SHADOW_BRUSH_TILE_M = 1.5;
const float HFN_SHADOW_BRUSH_CONTRAST = 1.4;
// Three tones of the production directional shadow term: core 0, mid, lit 1.
const float HFN_SHADOW_CUT_LOW = 0.34;
const float HFN_SHADOW_CUT_HIGH = 0.66;
const float HFN_SHADOW_MID_TONE = 0.45;

varying float hfn_shadow_spray;
varying vec3 hfn_shadow_legacy_pos;


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


// Legacy implementation from the project's actual older commits.

//// INTERIOR LEGACY SHADOW CONTRACT
// Recovered from 2026-09-22 bd11bdf (solid core / torn perimeter) and
// 2026-09-30 eae9776 + 34f1bf1 (local ink, quantised world warp).
// Values are the authored historical defaults, not a new procedural approximation.
// Isolated behind stylized_shadow_interior_mode; outdoor remains unchanged.
const float HFN_LEGACY_SHADOW_WARP_M = 0.28;
const float HFN_LEGACY_MACRO_FREQ = 0.42;
const float HFN_LEGACY_DETAIL_FREQ = 1.35;
const float HFN_LEGACY_SHADOW_PATTERN_THRESHOLD = 0.52;
const float HFN_LEGACY_SHADOW_BREAK_SOFTNESS = 0.055;
const float HFN_LEGACY_SHADOW_FLOOR = 0.035;
const float HFN_LEGACY_EDGE_LIGHT = 0.17;
const float HFN_LEGACY_LOCAL_STRENGTH = 0.45;

float hfn_legacy_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float hfn_legacy_value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = hfn_legacy_hash(i);
	float b = hfn_legacy_hash(i + vec2(1.0, 0.0));
	float c = hfn_legacy_hash(i + vec2(0.0, 1.0));
	float d = hfn_legacy_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float hfn_legacy_world_noise(vec3 world_pos, float scale) {
	vec3 p = world_pos * max(scale, 0.0001);
	float xz = hfn_legacy_value_noise(p.xz);
	float xy = hfn_legacy_value_noise(p.xy + vec2(17.0, 3.0));
	float yz = hfn_legacy_value_noise(p.yz + vec2(-5.0, 23.0));
	return xz * 0.50 + xy * 0.25 + yz * 0.25;
}

// Exact 34f1bf1 quantised-island warp, with historical .28/.12/.45/.28 constants.
vec3 hfn_legacy_world_warp(vec3 world_pos) {
	float macro_a = hfn_legacy_world_noise(world_pos + vec3(17.3, 0.0, -6.1), 0.12);
	float macro_b = hfn_legacy_world_noise(world_pos + vec3(-9.7, 3.1, 13.9), 0.12);
	float detail_a = hfn_legacy_world_noise(world_pos + vec3(2.6, -7.2, 5.8), 0.45);
	float detail_b = hfn_legacy_world_noise(world_pos + vec3(-4.4, 8.3, -12.7), 0.45);
	vec2 macro = vec2(macro_a, macro_b) * 2.0 - 1.0;
	vec2 detail = vec2(detail_a, detail_b) * 2.0 - 1.0;
	vec2 warp = mix(macro, detail, 0.28);
	float amplitude_noise = hfn_legacy_world_noise(world_pos + vec3(31.0, -11.0, 7.0), 0.12 * 0.47);
	float island = mix(0.42, 1.0, step(0.48, amplitude_noise));
	float amplitude = mix(island, amplitude_noise, 0.22);
	return vec3(warp.x, 0.0, warp.y) * HFN_LEGACY_SHADOW_WARP_M * amplitude;
}

// Sept 22 ragged edge: preserve the centre, break only the perimeter.
// For Omni/Spot the Sept 30 local branch retains ATTENUATION as a multiplier,
// so we do not replace the inverse-square/range falloff with an artificial 1.0.
float hfn_legacy_shadow_attenuation(float attenuation, bool directional, vec3 world_pos) {
	float base = clamp(attenuation, 0.0, 1.0);
	float physical_shadow = 1.0 - base;
	float macro = hfn_legacy_world_noise(world_pos, HFN_LEGACY_MACRO_FREQ);
	float detail = hfn_legacy_world_noise(world_pos + vec3(11.7, -4.3, 7.1), HFN_LEGACY_DETAIL_FREQ);
	float core_start = directional ? 0.48 : 0.72;
	float core_end = directional ? 0.68 : 0.94;
	float gate_end_start = directional ? 0.50 : 0.74;
	float gate_end = directional ? 0.72 : 0.96;
	float solid_core = smoothstep(core_start, core_end, physical_shadow);
	float perimeter_gate = smoothstep(0.10, 0.22, physical_shadow)
		* (1.0 - smoothstep(gate_end_start, gate_end, physical_shadow));
	float edge_field = physical_shadow * 0.56 + macro * 0.78 + (detail - 0.5) * 0.10 * 0.22;
	float ragged_edge = smoothstep(
		HFN_LEGACY_SHADOW_PATTERN_THRESHOLD - HFN_LEGACY_SHADOW_BREAK_SOFTNESS,
		HFN_LEGACY_SHADOW_PATTERN_THRESHOLD + HFN_LEGACY_SHADOW_BREAK_SOFTNESS, edge_field);
	float ink_mask = clamp(max(solid_core, ragged_edge * perimeter_gate), 0.0, 1.0);
	float edge_darkness = mix(HFN_LEGACY_EDGE_LIGHT, HFN_LEGACY_SHADOW_FLOOR, smoothstep(0.42, 0.72, macro));
	float ink_darkness = mix(edge_darkness, HFN_LEGACY_SHADOW_FLOOR, solid_core);
	if (directional) {
		return mix(1.0, ink_darkness, ink_mask * 0.95);
	}
	float local_ink = mix(base, base * ink_darkness, ink_mask);
	return mix(base, local_ink, HFN_LEGACY_LOCAL_STRENGTH);
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


// View-space LIGHT_VERTEX offset in the surface plane; also returns the paint field.
// noise_pos is metric and fixed to the surface: world for static meshes, model for movers.
vec4 hfn_shadow_prepare(vec3 noise_pos, vec3 view_normal, mat4 inv_view, mat4 view, float offset_scale) {
	float strength = clamp(stylized_shadow_strength, 0.0, 1.0);
	float indoor = clamp(stylized_shadow_interior_mode, 0.0, 1.0);
	float pixel_m = max(length(fwidth(noise_pos)), 1e-5);
	vec3 n = normalize((inv_view * vec4(view_normal, 0.0)).xyz);
	bool painted_edge = stylized_shadow_brush_mix > 1.5;
	float brush_mix = clamp(stylized_shadow_brush_mix, 0.0, 1.0);
	float brush = 0.0;
	if (brush_mix > 0.0) {
		brush = hfn_shadow_brush(noise_pos, n, pixel_m);
	}

	vec3 noise;
	float offset_m;
	float painted_field = 0.0;
	if (painted_edge) {
		// Broad silhouette wobble stays single-octave. A second, much lower-frequency field
		// decides where a stroke grows outward; those rare lobes are what can detach into
		// pigment islands instead of turning the whole penumbra into uniform fuzz.
		float keep = 1.0 - smoothstep(0.2, 0.45, HFN_PAINTED_OFFSET_FREQ * pixel_m);
		noise = hfn_shadow_noise3(noise_pos * HFN_PAINTED_OFFSET_FREQ + vec3(13.7, -5.1, 29.3)) * keep;
		float blob_keep = 1.0 - smoothstep(0.2, 0.45, HFN_PAINTED_BLOB_FREQ * pixel_m);
		float blob = hfn_shadow_noise3(noise_pos * HFN_PAINTED_BLOB_FREQ + vec3(-17.3, 9.1, 6.7)).x * blob_keep;
		painted_field = clamp(blob * 0.72 + brush * 0.22 + noise.x * 0.06, -1.0, 1.0);
		float lobe = smoothstep(0.38, 0.74, painted_field);
		offset_m = HFN_PAINTED_OFFSET_M * (0.58 + 0.30 * abs(brush) + 0.50 * lobe);
	} else {
		noise = hfn_shadow_fbm3(noise_pos, HFN_SHADOW_OFFSET_FREQ, pixel_m);
		offset_m = HFN_SHADOW_OFFSET_M;
	}
	vec3 tangent = noise - n * dot(noise, n);
	// Historical 34f1bf1 world-space lookup perturbation, including its
	// hard amplitude islands. Only the receiver lookup moves, not the mesh.
	vec3 current_warp = tangent * offset_m;
	vec3 old_warp = hfn_legacy_world_warp(noise_pos);
	vec3 offset = (view * vec4(mix(current_warp, old_warp, indoor)
		* offset_scale * strength, 0.0)).xyz;

	float spray = 0.0;
	if (painted_edge) {
		// One coherent field now controls both continuity and detached islands. Its spatial scale
		// is intentionally larger than the texture detail so the breakup reads as a few painted
		// decisions rather than noise sprinkled over every shadow edge.
		spray = painted_field;
	} else {
		if (brush_mix < 1.0) {
			spray = hfn_shadow_fbm3(noise_pos + vec3(41.3, -7.9, 23.1), HFN_SHADOW_SPRAY_FREQ, pixel_m).x;
			spray = clamp(spray * HFN_SHADOW_SPRAY_CONTRAST, -1.0, 1.0);
		}
		if (brush_mix > 0.0) {
			spray = mix(spray, brush, brush_mix);
		}
	}
	return vec4(offset, spray);
}


#define HFN_SHADOW_FRAGMENT_SCALED(noise_pos, offset_scale) vec4 hfn_prep = hfn_shadow_prepare(noise_pos, NORMAL, INV_VIEW_MATRIX, VIEW_MATRIX, offset_scale); LIGHT_VERTEX = VERTEX + hfn_prep.xyz; hfn_shadow_spray = hfn_prep.w; hfn_shadow_legacy_pos = noise_pos
#define HFN_SHADOW_FRAGMENT(world_pos) HFN_SHADOW_FRAGMENT_SCALED(world_pos, 1.0)


// Directional ATTENUATION is the shadow alone; local lights also carry distance
// falloff, so they keep only the torn lookup.
float hfn_stylized_shadow(float attenuation, bool directional) {
	float base = clamp(attenuation, 0.0, 1.0);
	float strength = clamp(stylized_shadow_strength, 0.0, 1.0);
	if (strength <= 0.0) {
		return base;
	}
	// Recover historical shadow logic in shelter: no new approximation, and
	// outside always keeps the 2026-10 production shadow contract.
	float indoor = clamp(stylized_shadow_interior_mode, 0.0, 1.0);
	if (indoor > 0.0) {
		float historical = hfn_legacy_shadow_attenuation(base, directional, hfn_shadow_legacy_pos);
		if (indoor >= 1.0) {
			return mix(base, historical, strength);
		}
		if (!directional) {
			return mix(base, historical, indoor * strength);
		}
		// Directional outdoor branch below still needs evaluation to blend.
	}
	if (!directional) {
		return base;
	}

	if (stylized_shadow_brush_mix > 1.5) {
		// Painted-edge breakup experiment. The physical dark core remains untouched. Past it,
		// a broad stroke exists only where the metre-scale field says pigment survived; farther
		// toward the light, a much higher threshold leaves sparse mid-tone islands. The last band
		// explicitly returns to the unmodified shadow map so open snow stays clean.
		float field = hfn_shadow_spray;
		float threshold_shift = field * HFN_PAINTED_EDGE_SHIFT;
		float continuous = smoothstep(0.12 + threshold_shift, 0.88 + threshold_shift, base);

		float stroke_zone = smoothstep(0.08, 0.22, base) * (1.0 - smoothstep(0.50, 0.70, base));
		float island_zone = smoothstep(0.46, 0.58, base) * (1.0 - smoothstep(0.80, 0.93, base));
		float stroke_mask = smoothstep(-0.44, 0.12, field);
		float island_mask = smoothstep(0.38, 0.74, field);

		float broken_stroke = mix(continuous, min(continuous, HFN_PAINTED_STROKE_TONE), stroke_zone * stroke_mask * 0.86);
		float with_islands = mix(broken_stroke, min(broken_stroke, HFN_PAINTED_ISLAND_TONE), island_zone * island_mask * 0.92);
		float clean_snow = smoothstep(0.88, 0.98, base);
		float painted = mix(with_islands, base, clean_snow);

		float active_edge = smoothstep(0.045, 0.18, base) * (1.0 - smoothstep(0.91, 0.985, base));
		float amount = clamp(active_edge * HFN_PAINTED_EDGE_AMOUNT, 0.0, 1.0) * strength;
		return mix(base, painted, amount);
	}

	float v = base + hfn_shadow_spray * 0.5 * HFN_SHADOW_SPRAY_JITTER;
	float tone = mix(step(HFN_SHADOW_CUT_LOW, v) * HFN_SHADOW_MID_TONE, 1.0, step(HFN_SHADOW_CUT_HIGH, v));
	float outdoor = mix(base, tone, strength);
	return mix(outdoor, hfn_legacy_shadow_attenuation(base, true, hfn_shadow_legacy_pos),
		clamp(stylized_shadow_interior_mode, 0.0, 1.0) * strength);
}


// Experimental colour mass and boundary stages. Their default zero strengths preserve
// hfn_stylized_shadow() exactly. Only the directional shadow is recoloured: local
// ATTENUATION also carries inverse-square falloff and the stove must stay untouched.
vec3 hfn_shadow_style_response(float attenuation, bool directional) {
	float physical = clamp(attenuation, 0.0, 1.0);
	float edge = clamp(stylized_shadow_edge_strength, 0.0, 1.0);
	if (directional && edge > 0.0) {
		float band = smoothstep(0.12, 0.32, physical)
			* (1.0 - smoothstep(0.70, 0.92, physical));
		float coarse = sin(hfn_shadow_legacy_pos.x * 2.1 + hfn_shadow_legacy_pos.z * 0.7)
			* sin(hfn_shadow_legacy_pos.z * 2.7 - hfn_shadow_legacy_pos.y * 0.6);
		float stroke = sin(hfn_shadow_legacy_pos.x * 5.1 - hfn_shadow_legacy_pos.z * 1.9);
		physical = clamp(physical + edge * band * (coarse * 0.23 + stroke * 0.07), 0.0, 1.0);
	}
	float tone = hfn_stylized_shadow(physical, directional);
	float mass = clamp(stylized_shadow_mass_strength, 0.0, 1.0);
	if (!directional || mass <= 0.0) {
		return vec3(tone);
	}
	float shade = 1.0 - smoothstep(0.18, 0.82, tone);
	vec3 pigment = vec3(0.16, 0.23, 0.29);
	return mix(vec3(tone), mix(vec3(tone), pigment, shade), mass);
}
