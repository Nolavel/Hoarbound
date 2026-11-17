extends SceneTree

## Key West Reality holds its blizzard: the scheduler never moves on, and an older save made in calm
## weather loads back into the blizzard. A profile without the hold still moves on.
## Run: godot --headless --script tests/systems/test_weather_hold.gd

const REALITY: String = "res://data/world_profiles/key_west_reality.tres"

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var held: WeatherController = _controller(load(REALITY) as WorldProfile)
	_check(held.get_current_profile() != null and held.get_current_profile().id == &"blizzard", "Reality does not start in the blizzard")
	held._advance_weather(72.0, true)
	_check(held.get_current_profile().id == &"blizzard", "the blizzard gave way to %s after 72 game hours" % held.get_current_profile().id)
	held.load_save_data({"profile_id": "calm", "remaining_h": 3.0, "then_id": ""})
	_check(held.get_current_profile().id == &"blizzard", "an old calm save replaced the held blizzard")
	var free_profile := WorldProfile.new()
	free_profile.initial_weather_profile_id = &"blizzard"
	var free: WeatherController = _controller(free_profile)
	var moved: bool = false
	for _i: int in range(40):
		free._advance_weather(3.0, true)
		moved = moved or free.get_current_profile().id != &"blizzard"
	_check(moved, "without the hold the weather never moved on")
	if _failures > 0:
		push_error("weather hold: %d check(s) failed" % _failures)
		quit(1)
		return
	print("weather hold: all checks passed")
	quit(0)


func _controller(profile: WorldProfile) -> WeatherController:
	var weather := WeatherController.new()
	weather.profiles = WeatherController.load_profiles_from(WeatherController.DEFAULT_PROFILE_DIR)
	weather.apply_world_profile(profile)
	root.add_child(weather)
	return weather


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("weather hold: " + message)
