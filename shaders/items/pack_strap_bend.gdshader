shader_type spatial;
render_mode world_vertex_coords, cull_disabled;

// The school backpack's straps bent along Henry's strap path (a spline mesh, as Unreal's SplineMeshComponent).
// Vertex in strap space, metres: x across, y off the body, z along; UV2.x is the side (0 or 1).

const int MAX_FRAMES = 96;
// Per side, MAX_FRAMES apart: centre (xyz) with its t along the strap (w), unit across with the row's
// half width (w), unit outward with how far the row's edges drop below its centre on the cloth (w).
uniform vec4 frame_centre[192];
uniform vec4 frame_across[192];
uniform vec4 frame_out[192];
uniform int frame_count_0 = 0;
uniform int frame_count_1 = 0;
uniform float strap_length_0 = 1.0;
uniform float strap_length_1 = 1.0;
uniform float gap = 0.001;
// Where each strap's pad ends (share of its length) and the pad's own half width: over the pad the strap
// spreads to the path's width, so it widens on the shoulder as the path's rows do.
uniform float pad_end_0 = 0.45;
uniform float pad_end_1 = 0.45;
uniform float pad_half = 0.0225;
// The strap's colour; the source texture (near black) gives only its weave and wear, relative to its mean.
uniform vec3 strap_colour : source_color = vec3(0.30, 0.32, 0.34);
uniform float texture_mean = 0.0055;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D metal_rough_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
#include "res://shaders/environment/materials/garment_frost.gdshaderinc"
varying vec3 v_frost_pos;
varying vec3 v_frost_normal;

void vertex() {
	v_frost_pos = VERTEX + vec3(UV2.x * 3.7, 0.0, 0.0);
	int side = UV2.x > 0.5 ? 1 : 0;
	int base = side * MAX_FRAMES;
	int count = side == 0 ? frame_count_0 : frame_count_1;
	float t = clamp(VERTEX.z / (side == 0 ? strap_length_0 : strap_length_1), 0.0, 1.0);
	int i = 0;
	for (int k = 1; k < MAX_FRAMES - 1; k++) {
		if (k > count - 2 || frame_centre[base + k].w > t) {
			break;
		}
		i = k;
	}
	vec4 c0 = frame_centre[base + i];
	vec4 c1 = frame_centre[base + i + 1];
	float f = clamp((t - c0.w) / max(c1.w - c0.w, 0.000001), 0.0, 1.0);
	vec4 a = mix(frame_across[base + i], frame_across[base + i + 1], f);
	vec4 o = mix(frame_out[base + i], frame_out[base + i + 1], f);
	vec3 along = normalize(c1.xyz - c0.xyz);
	vec3 out_dir = normalize(o.xyz - along * dot(o.xyz, along));
	vec3 across = cross(along, out_dir);
	float pad_end = side == 0 ? pad_end_0 : pad_end_1;
	float padness = 1.0 - smoothstep(pad_end - 0.05, pad_end, t);
	float x = VERTEX.x * mix(1.0, a.w / pad_half, padness);
	float r = x / max(a.w, 0.005);
	float drop = o.w * min(r * r, 1.5);
	vec3 centre = mix(c0.xyz, c1.xyz, f);
	vec3 n = NORMAL;
	vec3 tg = TANGENT;
	vec3 bn = BINORMAL;
	VERTEX = centre + across * x + out_dir * (VERTEX.y + gap - drop);
	NORMAL = normalize(across * n.x + out_dir * n.y + along * n.z);
	TANGENT = normalize(across * tg.x + out_dir * tg.y + along * tg.z);
	BINORMAL = normalize(across * bn.x + out_dir * bn.y + along * bn.z);
	v_frost_normal = NORMAL;
	if (count < 2) {
		VERTEX = vec3(0.0, -1000.0, 0.0);
	}
}

void fragment() {
	vec4 mr = texture(metal_rough_texture, UV);
	vec3 detail = texture(albedo_texture, UV).rgb / texture_mean;
	vec3 strap_albedo = clamp(strap_colour * mix(vec3(1.0), detail, 0.6), 0.0, 1.0);
	float strap_rough = mr.g;
	float strap_metal = mr.b;
	hfn_apply_garment_frost(strap_albedo, strap_rough, strap_metal, v_frost_pos, v_frost_normal, 0.0);
	ALBEDO = strap_albedo;
	ROUGHNESS = strap_rough;
	METALLIC = strap_metal;
	NORMAL_MAP = texture(normal_texture, UV).rgb;
}
