extends SceneTree

const POLICY: GDScript = preload("res://scripts/settings/native_resolution_policy.gd")
const CASES: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440),
	Vector2i(2560, 1080), Vector2i(3840, 2160), Vector2i(7680, 4320),
]

func _initialize() -> void:
	var failures: Array[String] = []
	for tier: float in [0.67, 0.77, 1.0]:
		var baseline: float = 1920.0 * 1080.0 * tier * tier
		for window_size: Vector2i in CASES:
			var native: float = POLICY.scale_for(window_size, tier, Window.CONTENT_SCALE_MODE_CANVAS_ITEMS)
			var legacy: float = POLICY.scale_for(window_size, tier, Window.CONTENT_SCALE_MODE_VIEWPORT)
			var pixels: float = POLICY.estimated_pixels(window_size, tier, Window.CONTENT_SCALE_MODE_CANVAS_ITEMS)
			if native <= 0.0 or native > 1.0 or pixels > baseline + 1.0:
				failures.append("over budget size=%s quality=%.2f scale=%.4f pixels=%.1f limit=%.1f" % [window_size, tier, native, pixels, baseline])
			if absf(legacy - tier) > 0.0001:
				failures.append("legacy scale changed")
			if window_size == Vector2i(1920, 1080) and absf(native - tier) > 0.0001:
				failures.append("1080p tier drift")
			print("NATIVE_BUDGET tier=%.2f window=%s native_scale=%.5f area=%.0f baseline=%.0f" % [tier, window_size, native, pixels, baseline])
	for t: String in failures:
		push_error(t)
	print("NATIVE_BUDGET_TEST: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
