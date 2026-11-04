extends ColorRect

## Isolated six-second UI glow demonstration; not a production inventory state owner.
const SEQUENCE_SECONDS: float = 6.0

@export var animation_enabled: bool = true

var _elapsed_seconds: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_preview_time(0.0)


func _process(delta: float) -> void:
	if not animation_enabled:
		return
	_elapsed_seconds = fmod(_elapsed_seconds + delta, SEQUENCE_SECONDS)
	set_preview_time(_elapsed_seconds)


func set_preview_time(seconds: float) -> void:
	var shader_material: ShaderMaterial = material as ShaderMaterial
	if shader_material != null:
		shader_material.set_shader_parameter("clock_seconds", seconds)
