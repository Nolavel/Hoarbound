extends SceneTree

## The production composition must attach its authored clock driver and advance a short fire stage.
var _failures: int = 0


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var world := (load("res://scenes/world/key_west/key_west_reality.tscn") as PackedScene).instantiate() as World
	root.add_child(world)
	await process_frame
	await process_frame
	var context: WorldContext = world.get_context()
	var clock := context.get_system(load("res://scripts/systems/time/simulation_clock.gd")) as SimulationClock
	var driver := context.find_in_scene(load("res://scripts/systems/world/DayNightManager.gd")) as DayNightManager
	var source := world.find_child("ShelterZone", true, false).get_node(^"Stove") as HeatSource
	_check(driver.simulation_clock == clock and clock.is_initialized(), "authored day/night driver detached from world clock")
	driver.set_process(false)
	source.add_logs(2)
	var rate: float = 24.0 / (driver.settings.day_duration + driver.settings.night_duration)
	source.start_loaded_fire(rate)
	driver._process(10.0)
	_check(is_equal_approx(source.get_intensity(), 0.54), "ten real seconds did not reach half intensity")
	driver._process(10.0)
	_check(is_equal_approx(source.get_intensity(), 1.0), "twenty real seconds did not develop fire")
	_check(clock._realtime_step_requests.is_empty(), "completed fire kept fine clock stepping")
	source.restore_fuel(4.0, false)
	source.start_loaded_fire(rate)
	driver.time_accelerator.is_accelerating = true
	driver.time_accelerator.acceleration_factor = 10.0
	driver._process(1.0)
	_check(is_equal_approx(source.get_intensity(), 0.54), "time acceleration did not advance warmup")
	clock.advance_hours(8.0, &"sleep")
	_check(not source.is_burning(), "sleep failed to finish warmup and burn fuel")
	print("test_stove_world_time: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("stove world time: " + message)
