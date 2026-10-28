shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
// A struck pane laid over the window: cracks radiate from the impact (state 1); broken (state 2),
// a jagged hole shows the dark room with shards left round the frame.

uniform float state = 1.0;
uniform vec2 impact = vec2(0.5); // pane UV of the strike
uniform float seed = 0.0;
uniform vec2 pane_size = vec2(1.0, 1.4); // metres, so cracks keep their width on any pane
uniform vec3 crack_colour : source_color = vec3(0.92, 0.95, 0.98);
uniform vec3 hole_colour : source_color = vec3(0.035, 0.04, 0.05);

float hash(float n) {
	return fract(sin(n * 127.1 + seed * 311.7) * 43758.5453);
}

// Angular noise around the impact: 0..1, smooth between `count` random spokes.
float spokes(float angle, float count) {
	float a = angle / 6.2832 * count;
	float i = floor(a);
	float f = fract(a);
	return mix(hash(i), hash(mod(i + 1.0, count)), smoothstep(0.0, 1.0, f));
}

void fragment() {
	vec2 d = (UV - impact) * pane_size;
	float r = length(d);
	float angle = atan(d.y, d.x) + 3.1416;
	float alpha = 0.0;
	vec3 colour = crack_colour;
	if (state > 1.5) {
		// The hole: its edge wanders with the angle; a band of shards hangs on beyond it.
		float edge = 0.28 + 0.32 * spokes(angle, 11.0) + 0.1 * spokes(angle * 3.0, 23.0);
		if (r < edge) {
			colour = hole_colour;
			alpha = 0.97;
		} else if (r < edge + 0.06) {
			alpha = 0.55;
		}
	}
	// Radial cracks: thin lines on the spoke angles, fading with distance; one ring near the strike.
	float n = 9.0;
	float spoke = abs(fract((angle / 6.2832) * n + hash(floor((angle / 6.2832) * n)) * 0.4) - 0.5);
	float line = 1.0 - smoothstep(0.0, 0.012 / max(r, 0.05), spoke);
	float reach = 0.35 + 0.5 * hash(floor((angle / 6.2832) * n) + 7.0);
	line *= 1.0 - smoothstep(reach * 0.6, reach, r);
	float ring = 1.0 - smoothstep(0.0, 0.006, abs(r - 0.11 - 0.03 * spokes(angle, 7.0)));
	float cracks = max(line, ring * step(r, 0.2));
	if (alpha < 0.9) {
		alpha = max(alpha, cracks * 0.9);
	}
	ALBEDO = colour;
	ALPHA = alpha;
}
