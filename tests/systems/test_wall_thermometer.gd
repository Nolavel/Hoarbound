extends SceneTree

## The 727 wall thermometer: column scale, room air from its zone, the reading fading with
## Henry's distance, and the shelter hanging one in the heated room.
## Run: godot --headless --script tests/systems/test_wall_thermometer.gd

var _failures: int = 0
var _frame: int = 0
var _thermometer: WallThermometer
var _henry: Node3D
var _zone: ThermalZone


## Runs from the first frame: nodes added in _initialize are not ready yet.
func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_setup()
	elif _frame == 3:
		_test_reading()
	elif _frame == 4:
		_test_fade()
		_test_shelter()
		_finish()
	return false


func _setup() -> void:
	_check(is_equal_approx(WallThermometer.column_fraction(0.0), 0.5), "0 °C does not fill half the tube")
	_check(is_equal_approx(WallThermometer.column_fraction(40.0), 1.0), "+40 °C does not fill the tube")
	_check(is_equal_approx(WallThermometer.column_fraction(-60.0), 0.0), "below the scale does not empty to the bulb")
	var thermal := ThermalManager.new()
	thermal.ambient_min_c = -20.0
	thermal.ambient_max_c = -20.0
	root.add_child(thermal)
	thermal.refresh_felt_temperature()
	_zone = ThermalZone.new()
	_zone.name = "Room"
	_zone.max_heated_offset_c = 20.0
	_zone.minimum_heated_offset_c = 20.0
	root.add_child(_zone)
	_henry = Node3D.new()
	_henry.add_to_group(&"player")
	root.add_child(_henry)
	_thermometer = WallThermometer.new()
	_thermometer.zone = _zone
	_thermometer.follow_rate = 1000.0
	root.add_child(_thermometer)


func _test_reading() -> void:
	var outdoor: float = (root.find_children("*", "ThermalManager", true, false)[0] as ThermalManager).get_outdoor_air_c()
	_check(is_equal_approx(_thermometer.get_air_c(), outdoor + _zone.get_total_offset_c()),
		"reading %.1f is not outdoor %.1f plus the zone" % [_thermometer.get_air_c(), outdoor])
	var before: float = _thermometer.get_air_c()
	_zone.restore_heated_offset(10.0)
	_check(_thermometer.get_air_c() > before + 5.0, "stove warmth in the room does not raise the reading (%.1f -> %.1f)" % [before, _thermometer.get_air_c()])
	var thermal := root.find_children("*", "ThermalManager", true, false)[0] as ThermalManager
	var warm: float = _zone.get_heated_offset_c()
	thermal._advance_hours(2.0, 12.0)
	_check(_zone.get_heated_offset_c() < warm - 1.0, "a room Henry is not in never cools (%.1f -> %.1f)" % [warm, _zone.get_heated_offset_c()])
	_check(TemperatureText.signed(-9.4) == "\u20139" and TemperatureText.signed(8.6) == "+9" and TemperatureText.signed(0.2) == "0",
		"signed degrees use a glyph IM Fell lacks")


func _test_fade() -> void:
	_check(_thermometer.get_reading_alpha() > 0.99, "the reading is hidden with Henry beside it")
	_henry.global_position = Vector3(0.0, 0.0, 3.5)
	_thermometer._process(0.016)
	_check(_thermometer.get_reading_alpha() < 0.01, "the reading shows from 3.5 m")


func _test_shelter() -> void:
	var shelter := KeyWest727Shelter.new()
	shelter.build()
	var found: Array[Node] = shelter.find_children("WallThermometer", "", true, false)
	_check(found.size() == 1 and found[0] is WallThermometer, "727 hangs no wall thermometer")
	if found.size() == 1:
		var hung := found[0] as WallThermometer
		_check(hung.zone != null and hung.zone.name == &"ShelterZone", "the thermometer does not read the heated room")
	shelter.free()


func _finish() -> void:
	if _failures > 0:
		push_error("wall thermometer: %d check(s) failed" % _failures)
		quit(1)
		return
	print("wall thermometer: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("wall thermometer: %s" % message)
