class_name ShelterShadowBinder
extends Node

## Presentation state only. ThermalManager decides whether Henry is indoors;
## the shadow shader keeps all local-light attenuation physical.
const THERMAL_SCRIPT: GDScript = preload("res://scripts/systems/survival/thermal_manager.gd")
const INTERIOR_MODE: StringName = &"stylized_shadow_interior_mode"
const EPSILON: float = 0.002

## Ease the silhouette change across doors instead of popping a global uniform.
@export_range(0.01, 1.0, 0.01) var transition_seconds: float = 0.24

var _thermal: ThermalManager
var _blend: float = 0.0
var _target: float = 0.0
var _written: float = -1.0


func _ready() -> void:
	_write(0.0)


func on_world_ready(context: WorldContext) -> void:
	_thermal = context.get_system(THERMAL_SCRIPT) as ThermalManager
	if _thermal == null:
		push_warning("ShelterShadowBinder: missing ThermalManager; keeping outdoor shadows.")
		return
	if not _thermal.sheltered_changed.is_connected(_on_sheltered_changed):
		_thermal.sheltered_changed.connect(_on_sheltered_changed)
	_on_sheltered_changed(_thermal.is_sheltered())


func _process(delta: float) -> void:
	if is_equal_approx(_blend, _target):
		return
	_blend = move_toward(_blend, _target, delta / maxf(transition_seconds, 0.01))
	_write(_blend)


func _on_sheltered_changed(is_sheltered: bool) -> void:
	_target = 1.0 if is_sheltered else 0.0


func get_blend() -> float:
	return _blend


func _write(value: float) -> void:
	if _written >= 0.0 and absf(_written - value) < EPSILON:
		return
	_written = value
	RenderingServer.global_shader_parameter_set(INTERIOR_MODE, value)


func _exit_tree() -> void:
	if is_instance_valid(_thermal) and _thermal.sheltered_changed.is_connected(_on_sheltered_changed):
		_thermal.sheltered_changed.disconnect(_on_sheltered_changed)
	_blend = 0.0
	_target = 0.0
	_written = -1.0
	_write(0.0)
