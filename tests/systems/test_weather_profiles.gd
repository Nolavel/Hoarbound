extends SceneTree

## Loads every shipped weather profile and checks the scheduler can run them.
## Run: godot --headless --script tests/systems/test_weather_profiles.gd

const PROFILE_DIR: String = "res://resources/weather"

var _failures: int = 0


func _initialize() -> void:
	var profiles: Array[WeatherProfile] = _load_profiles()
	_check(profiles.size() >= 4, "expected at least four weather profiles, found %d" % profiles.size())
	_check_ids_unique(profiles)
	_check_ranges(profiles)
	_check_scheduler_runs(profiles)
	_check_manual_only(profiles)
	if _failures > 0:
		push_error("weather: %d check(s) failed" % _failures)
		quit(1)
		return
	print("weather: all checks passed (%d profiles)" % profiles.size())
	quit(0)


func _load_profiles() -> Array[WeatherProfile]:
	var profiles: Array[WeatherProfile] = []
	var dir := DirAccess.open(PROFILE_DIR)
	if dir == null:
		_check(false, "cannot open %s" % PROFILE_DIR)
		return profiles
	for file_name: String in dir.get_files():
		var clean: String = file_name.trim_suffix(".remap")
		if not clean.ends_with(".tres"):
			continue
		var profile := load("%s/%s" % [PROFILE_DIR, clean]) as WeatherProfile
		if profile == null:
			_check(false, "%s did not load as a WeatherProfile" % clean)
			continue
		profiles.append(profile)
	return profiles


func _check_ids_unique(profiles: Array[WeatherProfile]) -> void:
	var seen: Dictionary = {}
	for profile: WeatherProfile in profiles:
		_check(profile.id != &"", "a profile has an empty id")
		_check(not seen.has(profile.id), "duplicate profile id '%s'" % profile.id)
		seen[profile.id] = true


func _check_ranges(profiles: Array[WeatherProfile]) -> void:
	for profile: WeatherProfile in profiles:
		var label: String = String(profile.id)
		_check(profile.weight > 0.0, "%s has a non-positive weight" % label)
		_check(
			profile.min_duration_h > 0.0 and profile.max_duration_h >= profile.min_duration_h,
			"%s has an invalid duration range" % label
		)
		_check(profile.blend_time_s > 0.0, "%s has a non-positive blend time" % label)
		_check(profile.wind_speed_mps >= 0.0, "%s has negative wind" % label)
		_check(profile.name_key != "", "%s has no localisation key" % label)


## Drives the controller through many hours and checks it keeps producing wind.
func _check_scheduler_runs(profiles: Array[WeatherProfile]) -> void:
	if profiles.is_empty():
		return
	var controller := WeatherController.new()
	controller.profiles = profiles
	root.add_child(controller)
	controller.initialize()

	var seen_profiles: Dictionary = {}
	var clock: float = 0.0
	for step: int in range(2000):
		clock = fmod(clock + 0.25, 24.0)
		controller._on_time_update(clock)
		var current: WeatherProfile = controller.get_current_profile()
		if current != null:
			seen_profiles[current.id] = true
	_check(seen_profiles.size() > 1, "scheduler never left the starting profile")
	_check(controller.get_wind_speed_mps() >= 0.0, "scheduler produced negative wind")

	if controller.get_parent() != null:
		controller.get_parent().remove_child(controller)
	controller.free()


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("weather: %s" % message)


## A manual-only profile (the test "clear") exists and the scheduler never picks it.
func _check_manual_only(profiles: Array[WeatherProfile]) -> void:
	var manual: Array = profiles.filter(func(p: WeatherProfile) -> bool: return p.manual_only)
	_check(manual.any(func(p: WeatherProfile) -> bool: return p.id == &"clear"), "no manual-only clear profile for tests")
	var controller := WeatherController.new()
	controller.profiles = profiles
	for _i: int in range(200):
		var picked: WeatherProfile = controller._pick_weighted()
		if picked.manual_only:
			_check(false, "the scheduler picked manual-only %s" % picked.id)
			break
	controller.free()
