extends SceneTree

## Extremity cold load, ThermalManager stage thresholds for the HUD and room warmth persistence.
## Run: godot --headless --script tests/systems/test_cold_readouts.gd

var _failures: int = 0


func _initialize() -> void:
	_test_extremities()
	_test_stage_thresholds()
	_test_room_warmth_persists()
	_test_air_day_curve()
	if _failures > 0:
		push_error("cold readouts: %d check(s) failed" % _failures)
		quit(1)
		return
	print("cold readouts: all checks passed")
	quit(0)


func _test_extremities() -> void:
	var cold := ExtremityCold.new()
	var hat_boots: Dictionary = {&"head": {"insulation_c": 3.0}, &"feet": {"insulation_c": 4.0}}
	for _i: int in range(12):
		cold.advance(0.25, -27.0, hat_boots)
	_check(cold.get_load(&"hands") > cold.get_load(&"head"), "bare hands must frost before a hatted head")
	_check(cold.get_load(&"hands") > 0.6, "bare hands at -27 °C barely frosted: %.2f" % cold.get_load(&"hands"))
	var dry := ExtremityCold.new()
	var wet := ExtremityCold.new()
	var soaked: Dictionary = {&"feet": {"insulation_c": 4.0, "wetness": 1.0}}
	for _i: int in range(8):
		dry.advance(0.25, -16.0, hat_boots)
		wet.advance(0.25, -16.0, soaked)
	_check(wet.get_load(&"feet") > dry.get_load(&"feet") + 0.15, "wet boots do not chill the feet more")
	var before: float = cold.get_load(&"hands")
	for _i: int in range(8):
		cold.advance(0.25, 12.0, hat_boots)
	_check(cold.get_load(&"hands") < before * 0.2, "warmth does not ease the frost: %.2f" % cold.get_load(&"hands"))
	_check(ExtremityCold.new().get_load(&"feet") == 0.0, "a fresh model starts frosted")
	var saved: Dictionary = wet.get_save_data()
	var restored := ExtremityCold.new()
	restored.load_save_data(saved)
	_check(is_equal_approx(restored.get_load(&"feet"), wet.get_load(&"feet")), "extremity load lost in save")
	restored.reset()
	_check(restored.get_load(&"feet") == 0.0, "reset left frost behind")


func _test_stage_thresholds() -> void:
	var thermal := ThermalManager.new()
	_check(absf(thermal.get_stage_threshold_normalised(ThermalManager.Stage.CHILLED) - (36.0 - 28.0) / 8.6) < 0.001, "CHILLED threshold off the HUD scale")
	_check(absf(thermal.get_stage_threshold_normalised(ThermalManager.Stage.HYPOTHERMIC) - (33.0 - 28.0) / 8.6) < 0.001, "HYPOTHERMIC threshold off the HUD scale")
	var data: Dictionary = thermal.get_save_data()
	_check(data.has("extremities"), "thermal save has no extremities")
	thermal.load_save_data({"body_temp_c": 35.0})
	_check(thermal.get_extremity_cold(&"hands") == 0.0, "an old save without extremities invented frost")
	thermal.free()


func _test_room_warmth_persists() -> void:
	var world := Node.new()
	root.add_child(world)
	var zone := ThermalZone.new()
	zone.name = "Room"
	zone.max_heated_offset_c = 20.0
	world.add_child(zone)
	var state := ShelterState.new()
	state._world = world
	state.adopt_zone(zone)
	zone.restore_heated_offset(9.5)
	var data: Dictionary = state.get_save_data()
	_check(is_equal_approx(float(data["heat"]["Room"]), 9.5), "room warmth not remembered: %s" % data.get("heat"))
	zone.restore_heated_offset(0.0)
	state.load_save_data(data)
	_check(is_equal_approx(zone.get_heated_offset_c(), 9.5), "room warmth not restored after load: %.2f" % zone.get_heated_offset_c())
	## A chunk streamed back in builds a new zone under its own parent with the same name.
	var chunk := Node.new()
	world.add_child(chunk)
	var fresh := ThermalZone.new()
	fresh.name = "Room"
	fresh.max_heated_offset_c = 20.0
	chunk.add_child(fresh)
	state.adopt_zone(fresh)
	_check(is_equal_approx(fresh.get_heated_offset_c(), 9.5), "a streamed-in room came back cold")
	zone.restore_heated_offset(50.0)
	_check(is_equal_approx(zone.get_heated_offset_c(), 20.0), "restored warmth beat the zone maximum")
	state.free()
	world.free()


## The default curve makes the air coldest before dawn and warmest mid-afternoon, and wraps at midnight.
func _test_air_day_curve() -> void:
	var thermal := ThermalManager.new()
	thermal.initialize()
	_check(thermal.ambient_curve != null, "no default air curve assigned")
	var dawn: float = thermal._sample_ambient_c(5.5)
	var afternoon: float = thermal._sample_ambient_c(14.5)
	_check(is_equal_approx(dawn, thermal.ambient_min_c), "05:30 is not the coldest hour: %.1f" % dawn)
	_check(is_equal_approx(afternoon, thermal.ambient_max_c), "14:30 is not the warmest hour: %.1f" % afternoon)
	_check(thermal._sample_ambient_c(21.0) < thermal._sample_ambient_c(17.0), "the evening does not cool")
	_check(absf(thermal._sample_ambient_c(0.0) - thermal._sample_ambient_c(23.999)) < 0.2, "the curve jumps at midnight")
	thermal.free()


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("cold readouts: %s" % message)
