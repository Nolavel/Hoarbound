class_name ClothingFrostComponent
extends Node

## Rime building on Henry's clothes outdoors in frost (faster in snowfall and wind) and melting off
## by a fire or in warm air. Its amount is drawn by the garment shader; nothing reads it back.

## Outdoor air at or above this grows no rime.
@export var forms_below_c: float = -2.0
## Seconds of −25 °C still air for bare cloth to crust over.
@export var build_s: float = 300.0
## Extra growth at full snowfall, and per metre per second of wind.
@export var snowfall_boost: float = 1.5
@export var wind_boost_per_mps: float = 0.08
## Seconds to melt off fully beside a fire, and in air at +5 °C.
@export var melt_by_fire_s: float = 45.0
@export var melt_in_warm_air_s: float = 180.0
@export var visual: HenryUALAnimation

var _thermal: ThermalManager
var _weather: WeatherController
var _frost: float = 0.0
var _shown: float = -1.0


## Given by Player once the world's systems exist.
func set_systems(thermal: ThermalManager, weather: WeatherController) -> void:
	_thermal = thermal
	_weather = weather


func get_frost() -> float:
	return _frost


func _process(delta: float) -> void:
	if _thermal == null:
		return
	var sheltered: bool = _thermal.is_sheltered()
	var air: float = _thermal.get_room_temperature_c() if sheltered else _thermal.get_outdoor_air_c()
	var snow: float = _weather.get_snowfall_density() if _weather != null else 0.0
	var wind: float = _weather.get_wind_speed_mps() if _weather != null else 0.0
	step(delta, air, sheltered, _near_fire(), snow, wind)


## One step from the air around Henry; split out so tests drive it directly.
func step(delta: float, air_c: float, sheltered: bool, near_fire: bool, snowfall: float, wind_mps: float) -> void:
	if near_fire:
		_frost = maxf(0.0, _frost - delta / maxf(melt_by_fire_s, 0.1))
	elif air_c > 0.0:
		_frost = maxf(0.0, _frost - delta / maxf(melt_in_warm_air_s, 0.1) * clampf(air_c / 5.0, 0.3, 2.0))
	elif not sheltered and air_c < forms_below_c:
		var cold: float = clampf((forms_below_c - air_c) / 23.0, 0.1, 1.3)
		var weather: float = 1.0 + snowfall_boost * clampf(snowfall, 0.0, 1.0) + wind_boost_per_mps * maxf(wind_mps, 0.0)
		_frost = minf(1.0, _frost + delta / maxf(build_s, 0.1) * cold * weather * (1.0 - _frost * 0.6))
	if visual != null and absf(_frost - _shown) > 0.004:
		_shown = _frost
		visual.set_frost(_frost)


func _near_fire() -> bool:
	var body := get_parent() as Node3D
	if body == null:
		return false
	for source: HeatSource in HeatSource.get_all():
		if source.get_offset_at(body.global_position) > 0.0:
			return true
	return false
