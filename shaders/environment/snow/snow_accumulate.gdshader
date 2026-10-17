shader_type canvas_item;
render_mode blend_disabled;

// Persistent deformation field, ping-ponged between two viewports.
// R: compression below the settled top. G: displaced snow piled above it.
// Keeping the two states separate prevents the same smoothing path from turning
// compacted floors and loose heaps into one soft signed-height blob.
uniform sampler2D previous : filter_nearest, repeat_disable;
// V1 persistence restores compression only; displaced mass intentionally starts
// at zero when a window region is restored until persistence v2 exists.
uniform sampler2D restore : filter_linear, repeat_disable;
uniform sampler2D contact_tex : filter_nearest, repeat_disable;
// Settled field: R snow top (world y), G depth, B cut away.
uniform sampler2D field : filter_linear, repeat_disable;
uniform float base_y = 0.0;
// The deformation field and contact capture have independent world windows.
uniform vec2 field_origin = vec2(0.0);
uniform float field_window_m = 25.6;
uniform vec2 contact_origin = vec2(0.0);
uniform float contact_window_m = 6.4;
// Discrete accepted plants survive until this accumulator pass consumes them.
// A: centre uv, first row of the inverse footprint basis.
// B: second inverse-basis row, press depth, active marker.
uniform int foot_stamp_count = 0;
uniform vec4 foot_stamp_a[16];
uniform vec4 foot_stamp_b[16];
// UV offset applied once when the window moves.
uniform vec2 shift_uv = vec2(0.0);
// Share of deformation that weather fills back in this frame.
uniform float fill = 0.0;
// Share of the settled depth a foot or body can pack down.
uniform float max_pack = 0.85;
// A print's walls shedding into it this frame: uv centre, uv radius, fill share.
uniform vec4 collapse = vec4(0.0);
// Highest rise a compression wall may keep per texel of run, metres.
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
// Highest a displaced heap may stand above the settled top, metres.
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

// Map a deformation-field UV through world XZ into the small contact capture.
// Outside the 6.4 m window there is deliberately no live contact.
float contact_height(vec2 field_uv) {
	vec2 world_xz = field_origin + field_uv * field_window_m;
	vec2 contact_uv = (world_xz - contact_origin) / contact_window_m;
	if (contact_uv.x < 0.0 || contact_uv.y < 0.0 || contact_uv.x > 1.0 || contact_uv.y > 1.0) {
		return base_y + 1000.0;
	}
	return texture(contact_tex, vec2(contact_uv.x, 1.0 - contact_uv.y)).r + base_y;
}

// A persistent plant event. Its inverse 2D basis was built from the foot's
// tangent-plane forward/right vectors, so road slope and camber are preserved.
float foot_stamp_depth(vec2 uv) {
	float pressed = 0.0;
	for (int i = 0; i < 16; i++) {
		if (i >= foot_stamp_count) {
			break;
		}
		vec4 a = foot_stamp_a[i];
		vec4 b = foot_stamp_b[i];
		vec2 d = uv - a.xy;
		vec2 local = vec2(dot(d, a.zw), dot(d, b.xy));
		float r2 = dot(local, local);
		if (r2 <= 1.0 && b.w > 0.5) {
			float edge = 1.0 - smoothstep(0.82, 1.0, r2);
			pressed = max(pressed, b.z * edge);
		}
	}
	return pressed;
}

// True where something on the contact layer holds the snow down at this texel:
// a wall touching a boot keeps its inside slope (Sumner's inside angle).
bool held(vec2 uv, vec3 settled) {
	float contact = contact_height(uv);
	return contact < settled.r + 0.02 && contact > settled.r - settled.g - 0.3;
}

// Heap raised by one boot: peaks just outside the sole, biased towards travel.
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
	float compression = texture(restore, uv).r;
	float displaced = 0.0;
	if (kept) {
		vec2 previous_state = texture(previous, from).rg;
		compression = previous_state.r;
		displaced = previous_state.g;
		// Compression walls steeper than the snow can hold shed into the pit.
		if (snow && !held(uv, settled)) {
			float here = compression;
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
				moved += k_edge * max(there - here - talus, 0.0);
				moved -= k_edge * max(here - there - talus, 0.0);
			}
			compression = here + moved;
		}
	}
	compression *= 1.0 - fill;
	displaced *= 1.0 - fill;
	// Fallen clumps raise the floor in lumps, most near the wall they broke from.
	if (collapse.w > 0.0) {
		float r = distance(uv, collapse.xy) / max(collapse.z, 1e-6);
		if (r < 1.0 && compression > 0.0) {
			float lumps = lump_noise(uv * 1024.0 / 3.0);
			compression *= 1.0 - collapse.w * (0.4 + 0.6 * lumps) * smoothstep(0.0, 1.0, r + 0.3);
		}
	}
	// Pushed powder now has its own positive state instead of negative compression.
	if (snow) {
		displaced += deposit(uv, deposit_l_a, deposit_l_b) + deposit(uv, deposit_r_a, deposit_r_b);
	}
	// B below 0.5 is softness (x0.49): wind crust holds a foot, powder lets it sink.
	float give = settled.g * max_pack * clamp(settled.b / 0.49, 0.0, 1.0);
	if (!snow) {
		compression = 0.0;
		displaced = 0.0;
	} else {
		// Guaranteed discrete plant path. This does not depend on a rendered contact
		// frame existing at the exact instant the animated boot touched down.
		compression = max(compression, min(foot_stamp_depth(uv), give));
		// Continuous body/item/sole capture. The contact camera is local, so its
		// sub-texel taps are converted back into deformation-field UV distance.
		float contact_texel_m = contact_window_m / float(textureSize(contact_tex, 0).x);
		vec2 half_texel = vec2(0.35 * contact_texel_m / field_window_m);
		float live_pressed = 0.0;
		for (int i = 0; i < 4; i++) {
			vec2 o = vec2(float(i % 2) * 2.0 - 1.0, float(i / 2) * 2.0 - 1.0) * half_texel;
			float contact = contact_height(uv + o);
			float into = settled.r - contact;
			if (into > 0.0 && contact > settled.r - settled.g - 0.3) {
				live_pressed += min(into, give);
			}
		}
		compression = max(compression, live_pressed * 0.25);
		compression = clamp(compression, 0.0, give);
		displaced = clamp(displaced, 0.0, min(rim_max, settled.g + 0.05));
	}
	COLOR = vec4(compression, displaced, 0.0, 1.0);
}
