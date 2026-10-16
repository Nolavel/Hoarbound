extends DayNightManager
class_name PainterlyDayNightManager

## Codex art-direction layer for weather-dependent cloud readability.
## Keep calm/default and full whiteout behavior intact; only strengthen the
## middle weather band so cloud bodies read as volume instead of white haze.
const MID_CLOUD_SHAPE_BOOST: float = 0.24
const MID_CLOUD_SHADOW_BOOST: float = 0.16
const MID_CLOUD_MASK_TOP_DROP: float = 0.045
const MID_CLOUD_PARALLAX_DETAIL_BOOST: float = 0.10


func apply_weather_visual_profile(profile: WeatherProfile) -> void:
	super.apply_weather_visual_profile(profile)
	if profile == null or sky_material == null:
		return

	var snow: float = clampf(profile.snowfall_density, 0.0, 1.0)
	## Build the boost after ordinary wind/sparse snow, hold it through the
	## authored snowfall band, then fade it back out before full blizzard.
	var mid_rise: float = smoothstep(0.12, 0.42, snow)
	var whiteout_fade: float = 1.0 - smoothstep(0.70, 0.95, snow)
	var mid_readability: float = clampf(mid_rise * whiteout_fade, 0.0, 1.0)
	if mid_readability <= 0.001:
		return

	var shape_contrast: float = float(sky_material.get_shader_parameter("cloud_shape_contrast"))
	var shadow_strength: float = float(sky_material.get_shader_parameter("cloud_shadow_strength"))
	var mask_top: float = float(sky_material.get_shader_parameter("cloud_mask_top"))
	var detail_weight: float = float(sky_material.get_shader_parameter("cloud_parallax_detail_weight"))

	sky_material.set_shader_parameter(
		"cloud_shape_contrast",
		clampf(shape_contrast + MID_CLOUD_SHAPE_BOOST * mid_readability, 0.0, 0.96)
	)
	sky_material.set_shader_parameter(
		"cloud_shadow_strength",
		clampf(shadow_strength + MID_CLOUD_SHADOW_BOOST * mid_readability, 0.0, 0.82)
	)
	sky_material.set_shader_parameter(
		"cloud_mask_top",
		clampf(mask_top - MID_CLOUD_MASK_TOP_DROP * mid_readability, 0.40, 0.95)
	)
	sky_material.set_shader_parameter(
		"cloud_parallax_detail_weight",
		clampf(detail_weight + MID_CLOUD_PARALLAX_DETAIL_BOOST * mid_readability, 0.0, 0.78)
	)
