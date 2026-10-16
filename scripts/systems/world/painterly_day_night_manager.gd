extends DayNightManager
class_name PainterlyDayNightManager

## Sky art direction: each weather keeps one readable cloud character, by day and by night.
## Wind sculpts cloud bodies, snow closes the deck, a blizzard veils it; at night the moon lights the deck.

const PAINTERLY_GROUP: StringName = &"painterly_atmosphere"
## Wind that starts and completes cloud sculpting (calm 0.5 m/s none, windy 8 m/s and blizzard full).
const SCULPT_WIND_START_MPS: float = 1.0
const SCULPT_WIND_FULL_MPS: float = 7.0
## Snowfall that starts and completes the heavy deck, and the blizzard veil that hides it again.
const DECK_SNOW_START: float = 0.06
const DECK_SNOW_FULL: float = 0.40
const VEIL_SNOW_START: float = 0.60
const VEIL_SNOW_FULL: float = 0.95
## Added on top of the base weather mapping at full readability; detail follows wind only.
const SHAPE_BOOST: float = 0.26
const SHADOW_BOOST: float = 0.24
const MASK_TOP_DROP: float = 0.06
const DETAIL_BOOST: float = 0.18
## Cloud body size (shader cloud_sag, lower = bigger bodies): wind builds bodies, snow merges them into a deck.
const SAG_WIND_SCALE: float = 0.68
const SAG_DECK_SCALE: float = 0.55
## Wind builds more cloud bodies: lowers the mask threshold (calm stays the authored baseline).
const SCULPT_COVERAGE_DROP: float = 0.05
## Sky share of the world fog: wind clears the air over the clouds, snow thickens it, a blizzard closes it.
const FOG_SKY_AFFECT_BASE: float = 0.25
const FOG_SKY_AFFECT_WINDY: float = 0.08
const FOG_SKY_AFFECT_WHITEOUT: float = 0.60
## The volumetric fog is lit by the ambient, so at night it greys the dark sky out: it keeps this share of its sky veil.
const NIGHT_VOLUMETRIC_SKY_SHARE: float = 0.25
## Lit cloud tops (shader cloud_top_light): fair clouds in calm, the crispest in wind, a grey deck in snow.
const TOP_LIGHT_CALM: float = 0.55
const TOP_LIGHT_WIND: float = 0.25
const TOP_LIGHT_DECK: float = 0.35
const TOP_LIGHT_VEIL: float = 0.30
## Moonlight on the cloud deck at night: its colour, the lift every night has, and the lift readability adds.
const MOON_CLOUD_LIGHT: Color = Color(0.70, 0.80, 1.05)
const MOON_LIFT_BASE: float = 0.45
const MOON_LIFT_READABLE: float = 0.55
## At night the lit side of the deck is the moon's: tops stay at least this lit (veiled in a blizzard).
const NIGHT_TOP_LIGHT: float = 0.65

var _sculpt: float = 0.0
var _readability: float = 0.0
var _fog_sky_affect: float = FOG_SKY_AFFECT_BASE
var _top_light: float = TOP_LIGHT_CALM
var _veil: float = 0.0


func apply_weather_visual_profile(profile: WeatherProfile) -> void:
	super.apply_weather_visual_profile(profile)
	if profile == null or sky_material == null:
		return
	var snow: float = clampf(profile.snowfall_density, 0.0, 1.0)
	_sculpt = smoothstep(SCULPT_WIND_START_MPS, SCULPT_WIND_FULL_MPS, profile.wind_speed_mps)
	var deck: float = smoothstep(DECK_SNOW_START, DECK_SNOW_FULL, snow)
	var veil: float = smoothstep(VEIL_SNOW_START, VEIL_SNOW_FULL, snow)
	_readability = maxf(_sculpt, deck) * (1.0 - veil)
	_boost(&"cloud_shape_contrast", SHAPE_BOOST * _readability, 0.0, 0.96)
	_boost(&"cloud_shadow_strength", SHADOW_BOOST * _readability, 0.0, 0.86)
	_boost(&"cloud_mask_top", -MASK_TOP_DROP * _readability, 0.40, 0.95)
	_boost(&"cloud_parallax_detail_weight", DETAIL_BOOST * _sculpt * (1.0 - veil), 0.0, 0.80)
	sky_material.set_shader_parameter(&"cloud_sag",
		settings.cloud_sag * lerpf(1.0, SAG_WIND_SCALE, _sculpt) * lerpf(1.0, SAG_DECK_SCALE, deck))
	var top_light: float = TOP_LIGHT_CALM + TOP_LIGHT_WIND * _sculpt - TOP_LIGHT_DECK * deck - TOP_LIGHT_VEIL * veil
	_top_light = clampf(top_light, 0.1, 0.85)
	_veil = veil
	_boost(&"cloud_coverage", -SCULPT_COVERAGE_DROP * _sculpt * (1.0 - veil), 0.20, 0.68)
	_fog_sky_affect = lerpf(lerpf(FOG_SKY_AFFECT_BASE, FOG_SKY_AFFECT_WINDY, _sculpt), FOG_SKY_AFFECT_WHITEOUT, veil)
	_update_environment_visuals(get_current_hour_float())


## How much the current weather lets cloud bodies read (0 calm or whiteout, 1 windy or snowfall).
func get_cloud_readability() -> float:
	return _readability


func _update_environment_visuals(game_hour: float) -> void:
	super._update_environment_visuals(game_hour)
	if sky_material == null:
		return
	var daylight: float = _calculate_day_progress(game_hour)
	var critical: float = _calculate_critical_night_factor(game_hour)
	var lift: float = (1.0 - daylight) * (MOON_LIFT_BASE + MOON_LIFT_READABLE * _readability) * (1.0 - 0.75 * critical)
	var cloud: Color = sky_material.get_shader_parameter(&"cloud_color")
	var moonlit: Color = cloud + MOON_CLOUD_LIGHT * lift
	moonlit.a = cloud.a
	sky_material.set_shader_parameter(&"cloud_color", moonlit)
	_apply_fog_sky_affect(daylight)
	var night_top: float = maxf(_top_light, NIGHT_TOP_LIGHT * (1.0 - _veil))
	sky_material.set_shader_parameter(&"cloud_top_light", lerpf(night_top, _top_light, daylight))
	for node: Node in get_tree().get_nodes_in_group(PAINTERLY_GROUP) if is_inside_tree() else []:
		(node as PainterlyAtmospherePass).set_daylight(daylight)


func _apply_fog_sky_affect(daylight: float) -> void:
	if not is_instance_valid(world_environment_node) or world_environment_node.environment == null:
		return
	world_environment_node.environment.fog_sky_affect = _fog_sky_affect
	world_environment_node.environment.volumetric_fog_sky_affect = _fog_sky_affect * lerpf(NIGHT_VOLUMETRIC_SKY_SHARE, 1.0, daylight)


func _boost(parameter: StringName, delta: float, low: float, high: float) -> void:
	sky_material.set_shader_parameter(parameter, clampf(float(sky_material.get_shader_parameter(parameter)) + delta, low, high))
