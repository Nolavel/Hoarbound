shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_lambert, specular_disabled;

// Rime laid over gear whose own material cannot take it (plain StandardMaterial3D: the mug, the tin,
// webbing and buckles). Drawn as each mesh's overlay while it is on Henry; see ClothingFrostComponent.
#include "res://shaders/environment/materials/garment_frost.gdshaderinc"

varying vec3 v_frost_pos;
varying vec3 v_frost_normal;

void vertex() {
	v_frost_pos = VERTEX;
	v_frost_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float rime = hfn_garment_frost_weight(v_frost_pos, v_frost_normal, 0.6);
	if (rime <= 0.002) {
		discard;
	}
	ALBEDO = HFN_GARMENT_FROST_COLOR;
	ROUGHNESS = 0.7;
	ALPHA = rime;
}
