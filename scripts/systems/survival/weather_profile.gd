class_name WeatherProfile
extends Resource

## Tuning data for one weather state. Designers edit these as .tres files,
## never as constants in code.

## Identifier used by WeatherController and by audio/VFX listeners.
@export var id: StringName = &"calm"

## Player-facing name key, resolved through localisation.
@export var name_key: String = "WEATHER_CALM"

@export_group("Temperature")
## Offset applied to the ambient air temperature, in degrees Celsius.
@export var ambient_offset_c: float = 0.0

@export_group("Wind")
## Sustained wind speed in metres per second, drives wind chill.
@export var wind_speed_mps: float = 0.0
## Extra speed reached by gusts, sampled with noise over time.
@export var gust_speed_mps: float = 0.0
## Seconds between gust peaks; lower means choppier wind.
@export var gust_period_s: float = 8.0
## Compass bearing the wind blows towards, in degrees. 0 is -Z, 90 is +X.
@export_range(0.0, 360.0) var wind_direction_deg: float = 0.0
## How far the bearing wanders either side, so a storm does not blow from one
## fixed quarter all night. Sampled from the same gust noise.
@export_range(0.0, 180.0) var wind_direction_jitter_deg: float = 15.0

@export_group("Precipitation")
## Snowfall density, 0.0 clear to 1.0 whiteout. Drives VFX and visibility.
@export_range(0.0, 1.0) var snowfall_density: float = 0.0
## Fog/visibility distance in metres; 0.0 means the profile does not clamp it.
@export var visibility_m: float = 0.0
## How fast exposed clothing soaks, in wetness units per hour.
@export var wetness_rate_per_hour: float = 0.0

@export_group("Snow cover")
## How much settled snow lies on up-facing surfaces, 0 bare to 1 buried.
## Presentation only; the island is never bare, so profiles stay above zero.
@export_range(0.0, 1.0) var snow_cover: float = 0.5

@export_group("Transition")
## Seconds to blend into this profile from the previous one.
@export var blend_time_s: float = 20.0
## Relative likelihood of this profile being picked by the weather scheduler.
@export var weight: float = 1.0
## Never picked by the scheduler; only set_weather() starts it (tests and captures).
@export var manual_only: bool = false
## Minimum and maximum time this profile stays active, in in-game hours.
@export var min_duration_h: float = 1.0
@export var max_duration_h: float = 4.0
