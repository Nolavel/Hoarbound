// Rime on what Henry wears and carries, 0 none to 1 crusted. Set per instance by ClothingFrostComponent,
// so a mug on his pack frosts while the same mug lying in the world does not. Characters only.
instance uniform float garment_frost : hint_range(0.0, 1.0) = 0.0;

const vec3 HFN_GARMENT_FROST_COLOR = vec3(0.84, 0.89, 0.95);

float hfn_gf_hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float hfn_gf_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hfn_gf_hash(i), hfn_gf_hash(i + vec3(1, 0, 0)), f.x),
			mix(hfn_gf_hash(i + vec3(0, 1, 0)), hfn_gf_hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hfn_gf_hash(i + vec3(0, 0, 1)), hfn_gf_hash(i + vec3(1, 0, 1)), f.x),
			mix(hfn_gf_hash(i + vec3(0, 1, 1)), hfn_gf_hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// Share of a fragment under rime. Cloth (film 0): a powdery veil that keeps the weave readable, denser on
// up-facing folds and in broad drifts, salted with crystal grains. Hard surfaces (film 1): an even matt
// bloom of finer crystals, as on cold metal and plastic. model_pos must ride with the object.
float hfn_garment_frost_weight(vec3 model_pos, vec3 world_normal, float film) {
	if (garment_frost <= 0.0) {
		return 0.0;
	}
	float facing_up = smoothstep(-0.4, 0.9, world_normal.y);
	float drift = hfn_gf_noise(model_pos * 6.0);
	float veil = garment_frost * mix(mix(0.3, 1.0, facing_up), mix(0.55, 0.9, facing_up), film)
		* mix(mix(0.55, 1.0, drift), mix(0.85, 1.0, drift), film);
	float grain_scale = mix(140.0, 260.0, film);
	float grain = hfn_gf_noise(model_pos * grain_scale) * 0.6 + hfn_gf_noise(model_pos * grain_scale * 0.43) * 0.4;
	float crystals = smoothstep(1.0 - veil * 0.8, 1.14 - veil * 0.8, grain);
	return clamp(veil * veil * 0.4 + crystals * veil * 0.6, 0.0, mix(0.75, 0.6, film));
}

void hfn_apply_garment_frost(inout vec3 frost_albedo, inout float frost_roughness, inout float frost_metallic, vec3 model_pos, vec3 world_normal, float film) {
	float rime = hfn_garment_frost_weight(model_pos, world_normal, film);
	frost_albedo = mix(frost_albedo, HFN_GARMENT_FROST_COLOR, rime);
	frost_roughness = mix(frost_roughness, 0.7, rime);
	frost_metallic = mix(frost_metallic, 0.0, rime);
}
