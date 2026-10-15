class_name PainterlyAtmospherePass
extends MeshInstance3D

## Fullscreen atmospheric value wash attached to the production TPS camera.
## It deliberately owns only distance fog, paper tooth and broad pigment breakup;
## object materials remain responsible for surface-bound brush language.

const ENABLE_SETTING := &"hfn/visual/painterly_atmosphere_enabled"

@export var effect_enabled: bool = true

var _material: ShaderMaterial


func _ready() -> void:
	layers = RenderLayers.SCREEN_PASS  # its vertex shader covers the screen of any camera that draws it
	_material = material_override as ShaderMaterial
	if _material == null:
		push_error("PainterlyAtmospherePass requires a ShaderMaterial override")
		visible = false
		return
	_sync_viewport_size()
	get_viewport().size_changed.connect(_sync_viewport_size)
	_apply_visibility()


func set_effect_enabled(value: bool) -> void:
	effect_enabled = value
	_apply_visibility()


func is_effect_enabled() -> bool:
	return visible


func get_shader_material() -> ShaderMaterial:
	return _material


func _apply_visibility() -> void:
	var project_enabled := bool(ProjectSettings.get_setting(ENABLE_SETTING, true))
	visible = effect_enabled and project_enabled and _material != null


func _sync_viewport_size() -> void:
	if _material == null:
		return
	_material.set_shader_parameter(&"viewport_size", get_viewport().get_visible_rect().size)
