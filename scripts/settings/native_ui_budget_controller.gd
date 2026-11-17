extends Node

## Window resize owner. GraphicsQuality.apply owns tier changes and calls the
## same pure policy directly; this observer only reapplies it when window resizes.
const GRAPHICS: GDScript = preload("res://scripts/settings/graphics_quality.gd")
const POLICY: GDScript = preload("res://scripts/settings/native_resolution_policy.gd")

func _ready() -> void:
	var window: Window = get_tree().root
	window.size_changed.connect(_on_window_resized)
	_on_window_resized()


func _on_window_resized() -> void:
	var window: Window = get_tree().root
	var tier_scale: float = float(GRAPHICS.current_profile()["render_scale"])
	window.scaling_3d_scale = POLICY.scale_for(window.size, tier_scale, window.content_scale_mode)
