extends SceneTree

## Gusts follow the profile's authored period: over a minute the wind sweeps most of its
## gust range, and it changes within one period. Guards the gust noise's time scale.
## Run: godot --headless --script tests/systems/test_weather_gusts.gd

const STEP_S: float = 0.1
const MINUTE_STEPS: int = 600

var _failures: int = 0


func _initialize() -> void:
	var profile := load("res://resources/weather/windy.tres") as WeatherProfile
	var weather := WeatherController.new()
	weather.profiles = [profile]
	root.add_child(weather)
	weather.initialize()
	weather.set_weather(profile.id, true)
	var speeds: PackedFloat32Array = []
	for _i: int in range(MINUTE_STEPS):
		weather._process(STEP_S)
		speeds.append(weather.get_wind_speed_mps())
	var low: float = speeds[0]
	var high: float = speeds[0]
	for speed: float in speeds:
		low = minf(low, speed)
		high = maxf(high, speed)
	print("gusts: %.2f..%.2f m/s over 60 s (base %.1f + gust %.1f, period %.1f s)" % [low, high,
		profile.wind_speed_mps, profile.gust_speed_mps, profile.gust_period_s])
	_check(high - low > profile.gust_speed_mps * 0.4, "a minute sweeps only %.2f of %.1f m/s gust range" % [high - low, profile.gust_speed_mps])
	var steps_per_period: int = roundi(profile.gust_period_s / STEP_S)
	var largest_step: float = 0.0
	for i: int in range(0, MINUTE_STEPS - steps_per_period, steps_per_period):
		largest_step = maxf(largest_step, absf(speeds[i + steps_per_period] - speeds[i]))
	_check(largest_step > profile.gust_speed_mps * 0.15, "wind barely moves within one gust period (%.2f m/s)" % largest_step)
	weather.free()
	if _failures > 0:
		push_error("weather gusts: %d check(s) failed" % _failures)
		quit(1)
	else:
		print("weather gusts: all checks passed")
		quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
