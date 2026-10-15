class_name PainterlyAtmospherePass
extends MeshInstance3D

## Fullscreen atmospheric value wash attached to the production TPS camera.
## It deliberately owns only distance fog, paper tooth and broad pigment breakup;
## object materials remain responsible for surface-bound brush language.

const ENABLE_SETTING := &"hfn/visual/painterly_atmosphere_enabled"
const WEATHER_GROUP: StringName = &"weather_controller"
## Sky share of the wash (docs/visual_fx_shaders.md): 10% in clear and ordinary snowfall weather,
## rising smoothly to 100% between ordinary snowfall and a blizzard as snowfall density grows.
const SKY_AFFECT_CLEAR: float = 0.1
const SKY_AFFECT_HEAVY: float = 1.0
const HEAVY_SNOW_START: float = 0.45
const HEAVY_SNOW_FULL: float = 0.95
## Whole-pass strength (owner rule): 10% without snow, rising with snowfall to 100% in a blizzard.
const WASH_CLEAR: float = 0.1
const WASH_FULL_SNOW: float = 0.95

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
	set_snowfall_density(0.0)
	_bind_weather.call_deferred()


func set_effect_enabled(value: bool) -> void:
	effect_enabled = value
	_apply_visibility()


func is_effect_enabled() -> bool:
	return visible


func get_shader_material() -> ShaderMaterial:
	return _material


## The wash's sky share for a snowfall density; the weather's own blend makes the change gradual.
static func sky_affect_for(snowfall_density: float) -> float:
	var heavy: float = smoothstep(HEAVY_SNOW_START, HEAVY_SNOW_FULL, snowfall_density)
	return lerpf(SKY_AFFECT_CLEAR, SKY_AFFECT_HEAVY, heavy)


## The wash's overall strength for a snowfall density: the wash is the snowstorm's, so calm weather barely shows it.
static func wash_strength_for(snowfall_density: float) -> float:
	return lerpf(WASH_CLEAR, 1.0, smoothstep(0.0, WASH_FULL_SNOW, snowfall_density))


func set_snowfall_density(snowfall_density: float) -> void:
	if _material != null:
		_material.set_shader_parameter(&"sky_affect", sky_affect_for(snowfall_density))
		_material.set_shader_parameter(&"wash_strength", wash_strength_for(snowfall_density))


func _apply_visibility() -> void:
	var project_enabled := bool(ProjectSettings.get_setting(ENABLE_SETTING, true))
	visible = effect_enabled and project_enabled and _material != null


func _bind_weather() -> void:
	var weather := get_tree().get_first_node_in_group(WEATHER_GROUP) as WeatherController
	if weather == null:
		return
	weather.conditions_updated.connect(_on_conditions_updated)
	set_snowfall_density(weather.get_snowfall_density())


func _on_conditions_updated(_ambient_offset_c: float, _wind_speed_mps: float, snowfall_density: float) -> void:
	set_snowfall_density(snowfall_density)


func _sync_viewport_size() -> void:
	if _material == null:
		return
	_material.set_shader_parameter(&"viewport_size", get_viewport().get_visible_rect().size)
