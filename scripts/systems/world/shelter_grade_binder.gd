class_name ShelterGradeBinder
extends Node

## Switches the shelter look on its edge: ThermalManager owns "inside"; the colour grade
## and the stylized shadow interior mode follow it over the same crossfade (#31).

const THERMAL_SCRIPT: GDScript = preload("res://scripts/systems/survival/thermal_manager.gd")
const GRADE_SCRIPT: GDScript = preload("res://scripts/systems/world/ColorGradeController.gd")
const SHADOW_INTERIOR_GLOBAL: StringName = &"stylized_shadow_interior_mode"

var _thermal: ThermalManager
var _grade: ColorGradeController
var _shadow_mode: float = 0.0
var _shadow_tween: Tween


func on_world_ready(context: WorldContext) -> void:
	_thermal = context.get_system(THERMAL_SCRIPT) as ThermalManager
	_grade = context.find_in_scene(GRADE_SCRIPT) as ColorGradeController
	if _thermal == null or _grade == null:
		push_warning("ShelterGradeBinder: thermal or colour grade missing, grade stays outdoor.")
		_set_shadow_mode(0.0)
		return
	if not _thermal.sheltered_changed.is_connected(_on_sheltered_changed):
		_thermal.sheltered_changed.connect(_on_sheltered_changed)
	_grade.initialize_for_interior(_thermal.is_sheltered())
	_set_shadow_mode(1.0 if _thermal.is_sheltered() else 0.0)


func _exit_tree() -> void:
	_set_shadow_mode(0.0)


func _on_sheltered_changed(is_sheltered: bool) -> void:
	if is_instance_valid(_grade):
		_grade.initialize_for_interior(is_sheltered)
		_fade_shadow_mode(1.0 if is_sheltered else 0.0, _grade.shelter_blend_s)


func _fade_shadow_mode(target: float, duration_s: float) -> void:
	if _shadow_tween != null and _shadow_tween.is_valid():
		_shadow_tween.kill()
	_shadow_tween = create_tween()
	_shadow_tween.tween_method(_set_shadow_mode, _shadow_mode, target, duration_s)


func _set_shadow_mode(value: float) -> void:
	_shadow_mode = value
	RenderingServer.global_shader_parameter_set(SHADOW_INTERIOR_GLOBAL, value)
