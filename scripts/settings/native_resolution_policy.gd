class_name NativeResolutionPolicy
extends RefCounted

## Keep the 3D pixel workload within the previous 1920x1080 GPU tier budget.
## canvas_items rerasterizes 2D UI at native resolution; 3D FSR scale is adapted.
## Geometry/shadows/postprocess and UI fill cost are NOT covered by this pixel budget.
const BASE := Vector2i(1920, 1080)

static func scale_for(window_size: Vector2i, quality_scale: float, stretch_mode: Window.ContentScaleMode) -> float:
	var tier_scale: float = clampf(quality_scale, 0.01, 1.0)
	if stretch_mode != Window.CONTENT_SCALE_MODE_CANVAS_ITEMS:
		return tier_scale
	var pixels: float = float(maxi(1, window_size.x)) * float(maxi(1, window_size.y))
	var allowed: float = float(BASE.x * BASE.y) * tier_scale * tier_scale
	# Scale is per axis, so pixel count is proportional to scale squared.
	# No lower clamp: clamping to 0.25 at 8K would VIOLATE the pixel budget.
	return minf(1.0, sqrt(allowed / pixels))


static func estimated_pixels(window_size: Vector2i, quality_scale: float, stretch_mode: Window.ContentScaleMode) -> float:
	var rendered_root := BASE if stretch_mode == Window.CONTENT_SCALE_MODE_VIEWPORT else window_size
	var scale := scale_for(window_size, quality_scale, stretch_mode)
	return float(rendered_root.x * rendered_root.y) * scale * scale
