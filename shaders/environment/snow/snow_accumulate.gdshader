shader_type canvas_item;
render_mode blend_disabled;

// Persistent packed-snow field, ping-ponged between two viewports.
// R: metres packed below the settled top, negative where displaced snow piles up.
// Model after Sumner, O'Brien & Hodgins 1999: a boot compresses part of the snow,
// displaces the rest onto a rim, and walls erode to their slope, conserving mass.
uniform sampler2D previous : filter_nearest, repeat_disable;
// Packing restored from stored tiles, already filled in for their age; read where
// the window has just moved onto ground the previous frame did not cover.
uniform sampler2D restore : filter_linear, repeat_disable;
uniform sampler2D contact_tex : filter_nearest, repeat_disable;
// Settled field: R snow top (world y), G depth, B cut away.
uniform sampler2D field : filter_linear, repeat_disable;
uniform float base_y = 0.0;
// UV offset applied once when the window moves.
uniform vec2 shift_uv = vec2(0.0);
// Share of the packing that fills back in this frame.
uniform float fill = 0.0;
// Share of the settled depth a foot or body can pack down.
uniform float max_pack = 0.85;
// A print's walls shedding into it this frame: uv centre, uv radius, fill share.
uniform vec4 collapse = vec4(0.0);
// Highest rise a wall may keep per texel of run, metres: loose powder and wind crust.
uniform float talus_powder = 0.02;
uniform float talus_crust = 0.12;
// Share of the excess moved across one texel edge this frame (Sumner's liquidity).
uniform float erode_rate = 0.08;
// Randomness of the moved share, so walls crumble in bits instead of melting evenly.
uniform float roughness = 0.6;
uniform float frame_seed = 0.0;
// Displaced snow per boot, left then right. A: uv centre, uv forward.
// B: uv half length, uv half width, metres raised at the rim peak, forward bias.
uniform vec4 deposit_l_a = vec4(0.0);
uniform vec4 deposit_l_b = vec4(0.0);
uniform vec4 deposit_r_a = vec4(0.0);
uniform vec4 deposit_r_b = vec4(0.0);
// Distance outside the sole where the displaced rim peaks, in uv.
uniform float rim_uv = 0.002;
// Highest a displaced rim may stand above the settled top, metres.
uniform float rim_max = 0.1;

float lump_noise(vec2 p) {
	return fract(sin(dot(floor(p), vec2(12.9898, 78.233))) * 43758.5453);
}

float edge_hash(vec2 key, float seed) {
	return fract(sin(dot(key, vec2(41.23, 17.71)) + seed * 7.137) * 24634.6345);
}

// 0 wind crust, 1 loose powder; B below 0.5 is softness scaled by 0.49.
float powder_at(float b) {
	return smoothstep(0.45, 0.95, b / 0.49);
}

// True where something on the contact layer holds the snow down at this texel:
// a wall touching a boot keeps its inside slope (Sumner's inside angle).
bool held(vec2 uv, vec3 settled) {
	float contact = texture(contact_tex, vec2(uv.x, 1.0 - uv.y)).r + base_y;
	return contact < settled.r + 0.02 && contact > settled.r - settled.g - 0.3;
}

// Rim raised by one boot: peaks just outside the sole, heaped towards its travel.
float deposit(vec2 uv, vec4 a, vec4 b) {
	if (b.z <= 0.0) {
		return 0.0;
	}
	vec2 d = uv - a.xy;
	vec2 side = vec2(-a.w, a.z);
	vec2 local = vec2(dot(d, a.zw), dot(d, side));
	float r = length(local / b.xy);
	if (r <= 1.0 || r > 4.0) {
		return 0.0;
	}
	float outside = (r - 1.0) * length(local) / r;
	float x = outside / rim_uv;
	float bias = 1.0 + b.w * dot(normalize(local), vec2(1.0, 0.0));
	float lumps = 0.6 + 0.8 * lump_noise(uv * 1024.0 / 2.0);
	return b.z * x * exp(1.0 - x) * bias * lumps;
}

void fragment() {
	vec2 uv = UV;
	vec2 from = uv + shift_uv;
	vec2 size = vec2(textureSize(previous, 0));
	vec2 texel = 1.0 / size;
	vec3 settled = texture(field, uv).rgb;
	bool snow = settled.b < 0.5;
	bool kept = from.x >= 0.0 && from.y >= 0.0 && from.x <= 1.0 && from.y <= 1.0;
	float packed = texture(restore, uv).r;
	if (kept) {
		packed = texture(previous, from).r;
		// Walls steeper than the snow can hold shed into the pit, mass for mass.
		// Each edge flux is symmetric, so both texels agree on what moved.
		if (snow && !held(uv, settled)) {
			float here = packed;
			float soft_here = powder_at(settled.b);
			vec2 pix = floor(uv * size);
			float moved = 0.0;
			for (int k = 0; k < 8; k++) {
				vec2 dir = vec2(float(k % 3) - 1.0, float(k / 3) - 1.0);
				if (k >= 4) {
					dir = vec2(float((k + 1) % 3) - 1.0, float((k + 1) / 3) - 1.0);
				}
				vec2 n_uv = uv + dir * texel;
				vec2 n_from = from + dir * texel;
				if (n_from.x < 0.0 || n_from.y < 0.0 || n_from.x > 1.0 || n_from.y > 1.0) {
					continue;
				}
				float there = texture(previous, n_from).r;
				float run = length(dir);
				// No snow can move across this edge at any softness.
				if (abs(there - here) <= min(talus_powder, talus_crust) * run) {
					continue;
				}
				vec3 n_settled = texture(field, n_uv).rgb;
				if (n_settled.b >= 0.5 || held(n_uv, n_settled)) {
					continue;
				}
				float soft = 0.5 * (soft_here + powder_at(n_settled.b));
				float talus = mix(talus_crust, talus_powder, soft) * run;
				float k_edge = erode_rate / run * mix(1.0, 2.0 * edge_hash(pix * 2.0 + dir, frame_seed), roughness);
				// Out: this texel stands higher (less packed) and sheds into there.
				moved += k_edge * max(there - here - talus, 0.0);
				// In: there stands higher and sheds onto this texel.
				moved -= k_edge * max(here - there - talus, 0.0);
			}
			packed = here + moved;
		}
	}
	packed *= 1.0 - fill;
	// Fallen clumps raise the floor in lumps, most near the wall they broke from.
	if (collapse.w > 0.0) {
		float r = distance(uv, collapse.xy) / max(collapse.z, 1e-6);
		if (r < 1.0 && packed > 0.0) {
			float lumps = lump_noise(uv * 1024.0 / 3.0);
			packed *= 1.0 - collapse.w * (0.4 + 0.6 * lumps) * smoothstep(0.0, 1.0, r + 0.3);
		}
	}
	// Snow a boot pushed aside heaps on the rim it leaves.
	if (snow) {
		packed -= deposit(uv, deposit_l_a, deposit_l_b) + deposit(uv, deposit_r_a, deposit_r_b);
	}
	// B below 0.5 is softness (x0.49): wind crust holds a foot, powder lets it sink.
	float give = settled.g * max_pack * clamp(settled.b / 0.49, 0.0, 1.0);
	packed = clamp(packed, -min(rim_max, settled.g + 0.05), give);
	if (!snow) {
		packed = 0.0;
	}
	// The contact camera looks up, so its image runs +x east and down-screen north.
	// Four sub-texel taps: a boot edge covers part of a texel and presses part-way,
	// so print outlines come out smooth instead of stair-stepped.
	if (snow) {
		vec2 half_texel = 0.35 / vec2(textureSize(contact_tex, 0));
		float pressed = 0.0;
		for (int i = 0; i < 4; i++) {
			vec2 o = vec2(float(i % 2) * 2.0 - 1.0, float(i / 2) * 2.0 - 1.0) * half_texel;
			float contact = texture(contact_tex, vec2(uv.x, 1.0 - uv.y) + o).r + base_y;
			float into = settled.r - contact;
			if (into > 0.0 && contact > settled.r - settled.g - 0.3) {
				pressed += min(into, give);
			}
		}
		packed = max(packed, pressed * 0.25);
	}
	COLOR = vec4(packed, 0.0, 0.0, 1.0);
}
