extends SceneTree

## Covers the seam between the weather and every snow shader: one writer, two
## globals, and snow and rime that are world state rather than a weather mirror.
## Run: godot --headless --script tests/systems/test_snow_presentation.gd

const SYSTEM_PATH: String = "res://scripts/systems/world/snow/snow_presentation_system.gd"

var _failures: int = 0


func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	_test_every_profile_carries_a_sane_cover()
	_test_a_fresh_world_starts_at_its_weather()
	_test_snow_builds_while_it_falls()
	_test_a_blizzard_does_not_vanish_when_it_stops()
	_test_warm_air_melts_it()
	_test_frost_grows_over_hours_not_instantly()
	_test_state_survives_a_save_round_trip()
	_test_storm_snow_builds_and_settles()
	_test_fresh_snow_is_loose_and_dry_cold_crusts_it()
	_test_the_globals_are_declared()
	_test_there_is_one_writer()
	_test_the_world_builds_it()
	if _failures > 0:
		push_error("snow: %d check(s) failed" % _failures)
		quit(1)
		return
	print("snow: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("snow: %s" % message)


func _dispose(node: Node) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()


func _profiles() -> Array[WeatherProfile]:
	return WeatherController.load_profiles_from("res://resources/weather")


func _test_every_profile_carries_a_sane_cover() -> void:
	var by_id: Dictionary = {}
	for profile: WeatherProfile in _profiles():
		_check(
			profile.snow_cover > 0.0 and profile.snow_cover <= 1.0,
			"'%s' has snow_cover %.2f; the island is never bare" % [profile.id, profile.snow_cover]
		)
		by_id[profile.id] = profile.snow_cover
	_check(
		float(by_id.get(&"blizzard", 0.0)) > float(by_id.get(&"calm", 1.0)),
		"a blizzard does not leave more snow than a calm day"
	)


func _make_weather(profile_id: StringName) -> WeatherController:
	var weather := WeatherController.new()
	weather.profiles = _profiles()
	weather.starting_profile_id = profile_id
	weather.scheduler_enabled = false
	root.add_child(weather)
	weather.initialize()
	return weather


func _make_thermal(air_c: float) -> ThermalManager:
	var thermal := ThermalManager.new()
	root.add_child(thermal)
	thermal._outdoor_air_c = air_c
	return thermal


func _make_system(weather: WeatherController, thermal: ThermalManager) -> SnowPresentationSystem:
	var system := SnowPresentationSystem.new()
	root.add_child(system)
	system._weather = weather
	system._thermal = thermal
	system.refresh()
	return system


func _test_a_fresh_world_starts_at_its_weather() -> void:
	var weather := _make_weather(&"calm")
	var system := _make_system(weather, null)
	_check(absf(system.get_written_snow_cover() - 0.35) < 0.01, "a calm world did not start at its 0.35")
	_dispose(system)
	_dispose(weather)


func _test_snow_builds_while_it_falls() -> void:
	var weather := _make_weather(&"calm")
	var system := _make_system(weather, _make_thermal(-10.0))
	weather.set_weather(&"blizzard", true)
	system.advance_hours(0.25)
	var early: float = system.get_settled_snow()
	_check(early > 0.35 and early < 1.0, "a quarter hour of blizzard left %.2f, expected partway" % early)
	system.advance_hours(3.0)
	_check(system.get_settled_snow() > 0.95, "three hours of blizzard left only %.2f" % system.get_settled_snow())
	_dispose(system)
	_dispose(weather)


## The whole reason the state exists: calm after a storm keeps the storm's snow.
func _test_a_blizzard_does_not_vanish_when_it_stops() -> void:
	var weather := _make_weather(&"blizzard")
	var system := _make_system(weather, _make_thermal(-10.0))
	weather.set_weather(&"calm", true)
	system.advance_hours(1.0)
	_check(system.get_settled_snow() > 0.9, "an hour after the blizzard the snow fell to %.2f" % system.get_settled_snow())
	system.advance_hours(48.0)
	_check(
		absf(system.get_settled_snow() - 0.35) < 0.01,
		"two calm days left %.2f, expected it settled to calm's 0.35" % system.get_settled_snow()
	)
	_dispose(system)
	_dispose(weather)


func _test_warm_air_melts_it() -> void:
	var weather := _make_weather(&"calm")
	var cold := _make_system(weather, _make_thermal(-5.0))
	var warm := _make_system(weather, _make_thermal(4.0))
	cold.advance_hours(6.0)
	warm.advance_hours(6.0)
	_check(warm.get_settled_snow() < cold.get_settled_snow(), "air above freezing melted nothing")
	_dispose(cold)
	_dispose(warm)
	_dispose(weather)


func _test_frost_grows_over_hours_not_instantly() -> void:
	var thermal := _make_thermal(2.0)
	var system := _make_system(null, thermal)
	_check(is_zero_approx(system.get_frost()), "rime formed above freezing")
	thermal._outdoor_air_c = -30.0
	system.advance_hours(1.0)
	var after_hour: float = system.get_frost()
	_check(after_hour > 0.1 and after_hour < 0.5, "an hour of deep cold grew %.2f rime, expected partway" % after_hour)
	system.advance_hours(10.0)
	_check(is_equal_approx(system.get_frost(), 1.0), "ten hours of deep cold did not finish the rime")
	_dispose(system)


func _test_state_survives_a_save_round_trip() -> void:
	var weather := _make_weather(&"blizzard")
	var system := _make_system(weather, _make_thermal(-15.0))
	system.advance_hours(5.0)
	var saved: Dictionary = system.get_save_data()
	_check(SaveManager.implements_save_contract(system), "the snow system does not implement the save contract")

	var fresh := _make_system(_make_weather(&"calm"), _make_thermal(-15.0))
	fresh.load_save_data(saved)
	_check(
		is_equal_approx(fresh.get_settled_snow(), system.get_settled_snow()),
		"a loaded save came back at %.2f, not the saved %.2f" % [fresh.get_settled_snow(), system.get_settled_snow()]
	)
	_dispose(system)
	_dispose(fresh)
	_dispose(weather)


## A shader that declares `global uniform` will not compile if the name is
## missing from project settings, so the declaration is part of the contract.
func _test_the_globals_are_declared() -> void:
	for name: StringName in [SnowPresentationSystem.GLOBAL_SNOW_COVER, SnowPresentationSystem.GLOBAL_FROST_AMOUNT, SnowPresentationSystem.GLOBAL_STORM_SHARE]:
		_check(
			ProjectSettings.has_setting("shader_globals/%s" % name),
			"shader global '%s' is not declared in project.godot" % name
		)


## Only SnowPresentationSystem may write the snow globals. Tools may set them
## for captures; game code may not.
func _test_there_is_one_writer() -> void:
	var offenders: Array[String] = []
	_scan_for_writers("res://scripts", offenders)
	_scan_for_writers("res://core", offenders)
	_scan_for_writers("res://world", offenders)
	_check(offenders.is_empty(), "other writers of the snow globals: %s" % str(offenders))


var _writer: RegEx = RegEx.create_from_string(
	"global_shader_parameter_set\\(\\s*&?\"?(snow_cover|frost_amount|GLOBAL_SNOW|GLOBAL_FROST|[A-Za-z_.]*GLOBAL_SNOW_COVER|[A-Za-z_.]*GLOBAL_FROST_AMOUNT)"
)


func _scan_for_writers(directory: String, offenders: Array[String]) -> void:
	var dir := DirAccess.open(directory)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		_scan_for_writers(directory.path_join(sub), offenders)
	for file_name: String in dir.get_files():
		if not file_name.ends_with(".gd"):
			continue
		var path: String = directory.path_join(file_name)
		if path == SYSTEM_PATH:
			continue
		## Only a set call naming snow_cover or frost_amount counts; other snow
		## globals (the shell's window and depth) have their own owner.
		if _writer.search(FileAccess.get_file_as_string(path)) != null:
			offenders.append(path)


func _test_the_world_builds_it() -> void:
	_check(
		World.WORLD_SYSTEM_SCRIPTS.has(load(SYSTEM_PATH)),
		"the composition root does not build the snow system"
	)


## A blizzard lays fresh snow in the storm pattern; calm lets it settle into the
## old base over hours, and the share survives a save.
func _test_storm_snow_builds_and_settles() -> void:
	var weather := _make_weather(&"calm")
	var system := _make_system(weather, null)
	var calm: float = system.get_storm_share()
	weather.set_weather(&"blizzard", true)
	system.advance_hours(3.0)
	var stormy: float = system.get_storm_share()
	_check(stormy > calm + 0.3, "a 3 h blizzard left the storm share at %.2f" % stormy)
	weather.set_weather(&"calm", true)
	system.advance_hours(1.0)
	_check(system.get_storm_share() > stormy - 0.1, "fresh storm snow settled within an hour")
	system.advance_hours(48.0)
	_check(absf(system.get_storm_share() - calm) < 0.01, "storm snow never settled into the base")
	var saved: Dictionary = system.get_save_data()
	var other := _make_system(weather, null)
	saved["storm"] = 0.8
	other.load_save_data(saved)
	_check(is_equal_approx(other.get_storm_share(), 0.8), "the storm share was not restored from a save")
	_dispose(other)
	_dispose(system)
	_dispose(weather)


## Snowfall buries the crust under loose snow; dry cold hardens it again over a day,
## a thaw leaves it soft. Survives a save.
func _test_fresh_snow_is_loose_and_dry_cold_crusts_it() -> void:
	var weather := _make_weather(&"calm")
	var thermal := _make_thermal(-15.0)
	var system := _make_system(weather, thermal)
	_check(system.get_firmness() > 0.9, "settled snow in -15 C starts as crust, got %.2f" % system.get_firmness())
	weather.set_weather(&"blizzard", true)
	system.advance_hours(3.0)
	_check(system.get_firmness() < 0.2, "three hours of blizzard left the crust at %.2f" % system.get_firmness())
	weather.set_weather(&"calm", true)
	system.advance_hours(2.0)
	var young: float = system.get_firmness()
	_check(young > 0.0 and young < 0.5, "two calm hours hardened the new snow to %.2f, expected a little" % young)
	system.advance_hours(36.0)
	_check(system.get_firmness() > 0.9, "a cold day and a half left the crust at %.2f" % system.get_firmness())
	thermal._outdoor_air_c = 3.0
	system.advance_hours(36.0)
	_check(system.get_firmness() < 0.1, "a thaw left the crust at %.2f" % system.get_firmness())
	var saved: Dictionary = system.get_save_data()
	saved["firmness"] = 0.7
	var other := _make_system(weather, _make_thermal(-15.0))
	other.load_save_data(saved)
	_check(is_equal_approx(other.get_firmness(), 0.7), "firmness was not restored from a save")
	_dispose(other)
	_dispose(system)
	_dispose(weather)
