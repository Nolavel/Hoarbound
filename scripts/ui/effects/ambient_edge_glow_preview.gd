extends ColorRect

## Preview-only driver for the stand-alone ambient edge-glow shader.
@export var animation_enabled: bool = true
@export_range(0.5, 30.0, 0.5) var cycle_seconds: float = 6.0

var _time: float = 0.0


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
    if not animation_enabled:
        return
    _time = fmod(_time + delta, maxf(cycle_seconds, 0.5))
    set_preview_time(_time)


func set_preview_time(seconds: float) -> void:
    var shader_material: ShaderMaterial = material as ShaderMaterial
    if shader_material != null:
        shader_material.set_shader_parameter("clock_seconds", seconds)
