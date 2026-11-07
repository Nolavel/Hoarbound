// Shared by the original canvas_item blob mask and the isolated 727 glass spatial test.
// Signed-distance smooth union. Do not change this without checking both callers.
float smooth_union(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / max(k, 0.00001), 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}
