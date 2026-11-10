// R&D #281, natural thaw: frost from a baked sheet of millimetre fern crystals and hoar, drawn as a layer that
// scatters the view behind it. It thaws by local need: soaks to glassy ice, breaks up, clears; the wet pane mists
// over with fine beads and sheds thin short runs. Test-only material for the FrontWindow1 probe.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

// Only its hash, noise and pane-size helpers are used; the frost itself comes from the sheet.
#include "res://shaders/environment/windows/frost_pattern.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
// R crystal lines, G hoar grains, B when frost reaches a texel (0 frame .. 1 middle), A smooth thickness.
uniform sampler2D frost_sheet : hint_default_black, repeat_disable, filter_linear_mipmap;
uniform vec3 crystal_white : source_color = vec3(0.965, 0.970, 0.972);
uniform vec3 hoar_grey : source_color = vec3(0.80, 0.85, 0.90);
uniform vec3 wet_ice : source_color = vec3(0.60, 0.68, 0.74);
uniform vec3 glass_tint : source_color = vec3(0.94, 0.965, 0.97);
uniform float heated_warmth : hint_range(0.0, 1.0) = 0.0;
uniform float growth_seed = 0.28;
uniform float melt_seed = 0.73;
uniform float pane_aspect = 1.81818;
// Same interface as the SDF probe: xy = a warm spot on the pane (UV), the rest is unused here.
uniform vec4 blob_data[16];
uniform int blob_count = 0;

const int LANES = 46;

// Warmth a texel needs before it starts to thaw. `sheet_ba` = the sheet's B and A there (a coarse mip will do):
// frost by the frame, low on the pane, far from the warm spots and thick all hold out longer.
float thaw_need(vec2 uv, vec2 sheet_ba) {
	float away = 0.9;
	for (int i = 0; i < 16; i++) {
		if (i >= blob_count) {
			break;
		}
		away = min(away, length((uv - blob_data[i].xy) * vec2(pane_aspect, 1.0)));
	}
	if (blob_count == 0) {
		away = length((uv - vec2(0.5, 0.42)) * vec2(pane_aspect, 1.0));
	}
	vec2 q = uv * vec2(pane_aspect, 1.0);
	float lobes = frost_value_noise(q * 2.3 + melt_seed * 7.1) * 0.65 + frost_value_noise(q * 6.1 + melt_seed * 3.3) * 0.35 - 0.5;
	float by_frame = 1.0 - sheet_ba.x;
	// Warm air rises along the glass: the upper pane leads, the sill lags.
	return 0.06 + 0.30 * by_frame * by_frame + 0.16 * clamp(away / 0.95, 0.0, 1.0) + 0.30 * uv.y * uv.y
		+ sheet_ba.y * 0.20 + lobes * 0.44;
}

// One layer of water beads scattered over a `cell_m` grid: xy = lens normal, z = bead mask, w = highlight.
vec4 beads(vec2 m, float cell_m, float seed, float grow, float density) {
	vec2 c = m / cell_m;
	vec2 base = floor(c);
	// Beads a pixel cannot hold fade out instead of shimmering.
	float px = length(fwidth(c));
	vec4 best = vec4(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 id = base + vec2(float(x), float(y));
			if (frost_hash21(id + seed * 13.7) > density) {
				continue;
			}
			vec2 centre = id + vec2(frost_hash21(id + 1.7 + seed), frost_hash21(id + 5.3 + seed));
			float r = mix(0.10, 0.34, pow(frost_hash21(id + 9.1 + seed), 2.0)) * grow;
			vec2 d = c - centre;
			d.y *= 0.86;  // a bead sags a little under its own weight
			float q = length(d) / max(r, 1e-4);
			float mask = (1.0 - smoothstep(0.82, 1.0, q)) * (1.0 - smoothstep(r * 0.9, r * 2.2, px));
			if (mask > best.z) {
				vec2 n = d / max(r, 1e-4);
				float glint = 1.0 - smoothstep(0.0, 0.34, length(n - vec2(-0.34, -0.42)));
				best = vec4(n * mask, mask, glint * mask);
			}
		}
	}
	return best;
}

void fragment() {
	vec2 pane = frost_pane_m(UV, VERTEX);
	vec2 m = UV * pane;
	float coverage = smoothstep(0.0, 0.25, COLOR.r);
	float t = heated_warmth * 0.96;
	vec4 sheet = texture(frost_sheet, UV);
	float lines = sheet.r;
	float hoar = sheet.g;
	float order = sheet.b;
	float body = sheet.a;

	// --- the frost: crystal feathers and hoar grains over a breath-thin film that thickens to the frame
	float film = mix(0.50, 0.07, smoothstep(0.10, 0.70, order)) * (0.75 + 0.5 * frost_value_noise(m * 14.0 + growth_seed * 9.0));
	float thick = coverage * (lines * 0.95 + hoar * 0.50 + film);

	// --- when this texel thaws
	float need = thaw_need(UV, vec2(order, body)) + lines * 0.05
		+ (frost_value_noise(m * 90.0 + melt_seed * 5.0) - 0.5) * 0.04;
	float s = (t - need) / 0.22;  // <0 dry, 0..0.6 soaking, 0.6..1 breaking up, >1 clear

	// --- runs: many, thin and short. A bead gathers where the frost soaks, creeps, lets go, and stops
	// as a hanging drop unless it has gathered enough to reach the sill.
	float track = 0.0;      // frost cleared along the run
	float track_wet = 0.0;  // frost soaked beside it
	float water = 0.0;
	vec2 water_n = vec2(0.0);
	float water_glint = 0.0;
	for (int k = 0; k < LANES; k++) {
		float lane = float(k);
		float h = frost_hash21(vec2(lane * 3.71 + melt_seed * 9.0, 6.13));
		float x0 = (lane + 0.1 + 0.8 * frost_hash21(vec2(lane, 2.9 + melt_seed))) / float(LANES);
		float y0 = mix(0.18, 0.93, frost_hash21(vec2(lane, 7.91 + melt_seed)));
		if (abs(UV.x - x0) * pane.x > 0.03 || UV.y < y0 - 0.01) {
			continue;
		}
		float start_need = thaw_need(vec2(x0, y0), textureLod(frost_sheet, vec2(x0, y0), 4.0).ba);
		float phase = clamp((t - start_need - 0.05) * mix(2.2, 4.0, h), 0.0, 1.0);
		if (phase <= 0.0) {
			continue;
		}
		float reach = mix(0.05, 0.34, h * h) / pane.y;  // 5..34 cm, most of them short
		float head = y0 + reach * phase * phase;
		float wander = (frost_value_noise(vec2(m.y * 14.0 + lane * 3.3, h * 9.2)) - 0.5) * 0.012
			+ (frost_value_noise(vec2(m.y * 60.0 + lane * 1.7, 4.4)) - 0.5) * 0.003;
		float dx = m.x - (x0 * pane.x + wander);
		float half_w = mix(0.0009, 0.0021, h);
		// A line a pixel cannot hold keeps a pixel's width and fades instead.
		float px = fwidth(m.x);
		float draw_w = max(half_w, px * 0.6);
		float fade = clamp(half_w / draw_w, 0.25, 1.0);
		float in_len = smoothstep(y0 - 0.003, y0 + 0.006, UV.y) * (1.0 - smoothstep(head - 0.002, head + 0.002, UV.y));
		track = max(track, (1.0 - smoothstep(draw_w * 0.9, draw_w * 1.5, abs(dx))) * in_len * fade);
		track_wet = max(track_wet, (1.0 - smoothstep(draw_w * 1.2, draw_w * 2.6, abs(dx))) * in_len * fade);
		float behind = (head - UV.y) * pane.y;
		float broken = mix(1.0, smoothstep(0.40, 0.62, frost_value_noise(vec2(m.y * 260.0 + lane * 9.0, h * 3.0))),
			smoothstep(0.01, 0.06, behind));
		float thread = (1.0 - smoothstep(draw_w * 0.5, draw_w, abs(dx))) * in_len * broken * fade;
		vec2 tip = vec2(dx, (UV.y - head) * pane.y + 0.0015);
		tip.y *= tip.y < 0.0 ? 0.5 : 1.0;  // teardrop: long above, round below
		float head_r = max(half_w * 1.7, px * 0.9);
		float bead = (1.0 - smoothstep(0.7, 1.0, length(tip) / head_r)) * clamp(half_w * 1.7 / head_r, 0.35, 1.0);
		float here = max(thread, bead);
		if (here > water) {
			water = here;
			water_n = bead > thread ? tip / head_r : vec2(dx / draw_w, 0.0);
			water_glint = 1.0 - smoothstep(0.0, 0.45, length(water_n - vec2(-0.36, bead > thread ? -0.40 : 0.0)));
		}
	}

	// --- what is left of the frost
	float soak = max(smoothstep(-0.15, 0.6, s), track_wet * 0.55);
	// It does not fade: it breaks into slush islands that shrink.
	float islands = frost_fbm(m * 30.0 + melt_seed * 23.0) * 0.6 + frost_value_noise(m * 120.0 + 8.3) * 0.4;
	float left = 1.0 - smoothstep(0.0, 1.0, (s - 0.6) * 2.5 - (islands - 0.5) * 1.6);
	left *= 1.0 - track * 0.9;
	// Soaking fuses grains and feathers into one sheet of clear ice before it goes.
	float fused = mix(thick, coverage * (body * 0.75 + film), soak * 0.7);
	float body_thick = fused * left * mix(1.0, 0.6, soak);
	float scatter = 1.0 - exp(-body_thick * mix(3.6, 1.1, soak));

	// --- mist and beads on wet glass: the pane fogs with fine drops as it warms, larger ones gather later
	float open = clamp(1.0 - left, 0.0, 1.0) * smoothstep(0.02, 0.2, t);
	float damp = max(open, soak * 0.8) * smoothstep(0.03, 0.25, t);
	float fresh = 1.0 - smoothstep(1.2, 4.5, s);  // it dries in the end
	vec4 mist = beads(m, 0.0052, melt_seed + 0.4, damp * fresh, 0.72);
	vec4 big = beads(m + 0.37, 0.016, melt_seed, open * mix(0.5, 1.0, fresh), 0.34 * mix(0.3, 1.0, fresh));
	// Too far to see single drops, mist still reads as a soft bloom on the glass.
	float far = smoothstep(0.0006, 0.0025, fwidth(m.x));  // 0 close up, 1 where a mist drop is under a pixel
	float fog = damp * fresh * (0.55 + 0.45 * frost_value_noise(m * 26.0 + melt_seed)) * far;

	// --- the view through: blurred by frost and mist, bent by water
	vec2 lens = water_n * water * 0.006 + big.xy * 0.008 + mist.xy * 0.003;
	vec2 jitter = (vec2(hoar, lines) - 0.5) * 0.004 * scatter;
	float blur = max(5.4 * clamp(body_thick * 1.8, 0.0, 1.0), 2.2 * fog) * (1.0 - max(water, big.z));
	vec3 view = textureLod(screen_tex, SCREEN_UV - lens + jitter, blur).rgb * glass_tint;
	view = mix(view, view * 0.94 + vec3(0.05), fog * 0.6);

	// --- the frost itself: white crystals on grey-blue hoar, glassy grey where soaked
	float bright = clamp(lines * 1.15 + hoar * 0.35, 0.0, 1.0);
	vec3 frost = mix(hoar_grey, crystal_white, max(bright, smoothstep(0.35, 1.0, body_thick) * 0.8));
	frost = mix(frost, wet_ice, soak * 0.60);
	// Glassy ice catches the light along its ridges; dry frost only glints here and there.
	vec2 slope = vec2(dFdx(body), dFdy(body));
	float ridge = clamp((slope.x + slope.y) * -9.0, -0.12, 0.30);
	frost += vec3(ridge) * soak * left;
	float sparkle = step(0.990, frost_hash21(floor(m * 700.0) + growth_seed)) * (1.0 - soak) * lines;
	frost += vec3(sparkle * 0.5);

	vec3 col = mix(view, frost, scatter);
	float rim_q = max(length(big.xy), length(mist.xy));
	col *= 1.0 - 0.24 * smoothstep(0.55, 1.0, rim_q);
	col *= 1.0 - 0.10 * water * smoothstep(0.3, 1.0, water_n.x);
	col += vec3(0.95, 0.98, 1.0) * (water_glint * water * 0.45 + big.w * 0.6 + mist.w * 0.4);
	ALBEDO = col;
	ALPHA = 1.0;
}
