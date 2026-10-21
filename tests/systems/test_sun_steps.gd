extends SceneTree

## The sun turns in steps so cascaded shadows hold still between them: no turn inside a step,
## an eased turn at a step edge, a snap on a jump. Run: godot --headless --script tests/systems/test_sun_steps.gd

var _failures: int = 0


func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	var manager := DayNightManager.new()
	var settings := DayNightSettings.new()
	settings.sun_step_minutes = 4
	settings.sun_blend_seconds = 2.0
	manager.settings = settings
	var light := DirectionalLight3D.new()
	manager.directional_light = light
	manager.total_game_time_hours = 10.0
	manager._aim_sun(10.0, true)
	var start: Quaternion = light.quaternion
	_check(start.angle_to(_sun(manager, 10.0)) < 2e-3, "snap did not aim at the step's sun")
	manager.total_game_time_hours = 10.0 + 3.0 / 60.0
	manager._aim_sun(10.05, false)
	manager._ease_sun(1.0)
	_check(light.quaternion.is_equal_approx(start), "the sun turned inside a step")
	manager.total_game_time_hours = 10.0 + 4.0 / 60.0
	manager._aim_sun(manager.total_game_time_hours, false)
	_check(light.quaternion.is_equal_approx(start), "a new step jumped instead of easing")
	var target: Quaternion = _sun(manager, 10.0 + 4.0 / 60.0)
	manager._ease_sun(1.0)
	var half: float = light.quaternion.angle_to(start)
	_check(half > 0.0 and half < target.angle_to(start), "the ease is not between the steps")
	manager._ease_sun(1.5)
	_check(light.quaternion.angle_to(target) < 2e-3, "the ease did not land on the new step")
	manager.total_game_time_hours = 12.0
	manager._aim_sun(12.0, false)
	_check(light.quaternion.angle_to(_sun(manager, 12.0)) < 2e-3, "a clock jump eased instead of snapping")
	light.free()
	settings.free()
	manager.free()
	if _failures > 0:
		push_error("sun steps: %d check(s) failed" % _failures)
		quit(1)
		return
	print("sun steps: all checks passed")
	quit(0)


func _sun(manager: DayNightManager, hour: float) -> Quaternion:
	var euler := Vector3(deg_to_rad(-manager._calculate_light_altitude(hour)), deg_to_rad(manager._calculate_light_azimuth(hour)), 0.0)
	return Basis.from_euler(euler).get_rotation_quaternion()


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("sun steps: %s" % message)
