class_name ColorGradeBlendPass
extends MeshInstance3D

## Fullscreen dual-LUT grade used only while ColorGradeController is blending.

const ENABLE_SETTING := &"hfn/visual/color_grade_blend_enabled"

@export var effect_enabled: bool = true

var _material: ShaderMaterial
var _active: bool = false


func _ready() -> void:
	add_to_group(&"color_grade_blend_pass")
	layers = RenderLayers.SCREEN_PASS
	_material = material_override as ShaderMaterial
	if _material == null:
		push_error("ColorGradeBlendPass requires a ShaderMaterial override")
		visible = false
		return
	_apply_visibility()


func is_effect_enabled() -> bool:
	return effect_enabled and bool(ProjectSettings.get_setting(ENABLE_SETTING, true))


func set_blend_active(active: bool) -> void:
	_active = active
	_apply_visibility()


func is_blend_active() -> bool:
	return _active and visible


func configure(
	lut_from: Texture3D,
	lut_to: Texture3D,
	weight: float,
	brightness_from: float,
	brightness_to: float,
	contrast_from: float,
	contrast_to: float,
	saturation_from: float,
	saturation_to: float
) -> void:
	if _material == null:
		return
	_material.set_shader_parameter(&"lut_from", lut_from)
	_material.set_shader_parameter(&"lut_to", lut_to)
	_material.set_shader_parameter(&"blend_weight", clampf(weight, 0.0, 1.0))
	_material.set_shader_parameter(&"brightness_from", brightness_from)
	_material.set_shader_parameter(&"brightness_to", brightness_to)
	_material.set_shader_parameter(&"contrast_from", contrast_from)
	_material.set_shader_parameter(&"contrast_to", contrast_to)
	_material.set_shader_parameter(&"saturation_from", saturation_from)
	_material.set_shader_parameter(&"saturation_to", saturation_to)


func _apply_visibility() -> void:
	visible = is_effect_enabled() and _active and _material != null
