shader_type canvas_item;
render_mode blend_disabled;

// Persistent deformation-state v2, ping-ponged between two viewports.
// R: compression below settled top (metres).
// G: displaced snow piled above it (metres).
// B: broken crust / disturbance (0..1).
// A: compacted density / age reserve (0..1; currently density-biased).
uniform sampler2D previous : filter_nearest, repeat_disable;
// Persistence v2 restores R+G. Older RF restores still work because missing G samples as 0.
uniform sampler2D restore : filter_linear, repeat_disable;
uniform sampler2D contact_tex : filter_nearest, repeat_disable;
// Settled field: R snow top (world y), G depth, B cut away / softness below 0.5.
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

// Heap raised by one boot. The main ridge sits outside the sole, but the forward
// lobe carries more mass and the ridge is quantized into centimetre-scale clumps.
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
	float forward = clamp(local.x / max(b.x * 3.0, 1e-6), -1.0, 1.0);
	float directional = 1.0 + b.w * mix(-0.55, 1.35, forward * 0.5 + 0.5);
	vec2 clump_cell = floor(uv * vec2(textureSize(previous, 0)) / 3.0);
	float clump = 0.48 + 0.92 * lump_noise(clump_cell + floor(a.xy * 97.0));
	float ridge = x * exp(1.0 - x);
	return b.z * ridge * directional * clump;
}

void fragment() {
	vec2 uv = UV;
	vec2 from = uv + shift_uv;
	vec2 size = vec2(textureSize(previous, 0));
	vec2 texel = 1.0 / size;
	vec3 settled = texture(field, uv).rgb;
	bool snow = settled.b < 0.5;
	bool kept = from.x >= 0.0 && from.y >= 0.0 && from.x <= 1.0 && from.y <= 1.0;
	vec4 restored = texture(restore, uv);
	float compression = max(restored.r, 0.0);
	float displaced = max(restored.g, 0.0);
	float disturbance = 0.0;
	float density = 0.0;
	if (kept) {
		vec4 previous_state = texture(previous, from);
		compression = max(previous_state.r, 0.0);
		displaced = max(previous_state.g, 0.0);
		disturbance = clamp(previous_state.b, 0.0, 1.0);
		density = clamp(previous_state.a, 0.0, 1.0);
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
			compression = max(here + moved, 0.0);
		}
	}

	// Snowfall/refill removes visible deformation first. Broken crust and density
	// recover more slowly so an old track does not instantly become virgin snow.
	compression *= 1.0 - fill;
	displaced *= 1.0 - fill;
	disturbance *= 1.0 - fill * 0.72;
	density *= 1.0 - fill * 0.42;

	// Fallen clumps raise the floor in lumps, most near the wall they broke from.
	if (collapse.w > 0.0) {
		float r = distance(uv, collapse.xy) / max(collapse.z, 1e-6);
		if (r < 1.0 && compression > 0.0) {
			float lumps = lump_noise(uv * size / 3.0);
			float fall_share = collapse.w * (0.4 + 0.6 * lumps) * smoothstep(0.0, 1.0, r + 0.3);
			compression *= 1.0 - fall_share;
			disturbance = max(disturbance, fall_share * 0.85);
		}
	}

	// Pushed powder has its own positive state instead of negative compression.
	if (snow) {
		float deposited = deposit(uv, deposit_l_a, deposit_l_b) + deposit(uv, deposit_r_a, deposit_r_b);
		displaced += deposited;
		float heap_share = clamp(deposited / max(rim_max, 0.001), 0.0, 1.0);
		disturbance = max(disturbance, heap_share * 0.42);
		// Freshly pushed powder is loose even next to a dense print floor.
		density = mix(density, min(density, 0.16), heap_share);
	}

	// B below 0.5 is softness (x0.49): wind crust holds a foot, powder lets it sink.
	float give = settled.g * max_pack * clamp(settled.b / 0.49, 0.0, 1.0);
	if (!snow) {
		compression = 0.0;
		displaced = 0.0;
		disturbance = 0.0;
		density = 0.0;
	} else {
		// Guaranteed discrete plant path. This does not depend on a rendered contact
		// frame existing at the exact instant the animated boot touched down.
		float stamped = min(foot_stamp_depth(uv), give);
		compression = max(compression, stamped);
		float stamp_share = stamped / max(give, 0.001);
		float crust_share = 1.0 - powder_at(settled.b);
		float slab_hash = edge_hash(floor(uv * size / 3.0), 17.0);
		float slab_break = mix(0.35, 1.0, smoothstep(0.2, 0.8, slab_hash));
		disturbance = max(disturbance, stamp_share * mix(0.24, 1.0, crust_share) * slab_break);
		density = max(density, stamp_share * mix(0.72, 0.96, crust_share));

		// Continuous body/item contact remains for deep wade and irregular objects.
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
		float body_press = live_pressed * 0.25;
		compression = max(compression, body_press);
		float body_share = body_press / max(give, 0.001);
		disturbance = max(disturbance, body_share * mix(0.18, 0.72, crust_share));
		density = max(density, body_share * 0.82);

		compression = clamp(compression, 0.0, give);
		displaced = clamp(displaced, 0.0, min(rim_max, settled.g + 0.05));
		disturbance = clamp(disturbance, 0.0, 1.0);
		density = clamp(density, 0.0, 1.0);
	}
	COLOR = vec4(compression, displaced, disturbance, density);
}
