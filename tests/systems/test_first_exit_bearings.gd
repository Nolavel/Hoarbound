extends SceneTree

## First Exit compass state: one shelter from landmark data, scenario arming,
## thermal arrival, recall, and a save that predates the system.
## Run: godot --headless --script tests/systems/test_first_exit_bearings.gd

var _failures: int = 0


func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	_check_bearings()
	_check_slot()
	_check_camera()
	_check_catalog()
	_check_lifecycle()
	_check_zones()
	_check_save()
	if _failures > 0:
		push_error("first exit bearings: %d check(s) failed" % _failures)
		quit(1)
		return
	print("first exit bearings: all checks passed")
	quit(0)


func _check_bearings() -> void:
	var north: float = FirstExitBearings.bearing_of(Vector2.ZERO, Vector2(0, -10))
	var east: float = FirstExitBearings.bearing_of(Vector2.ZERO, Vector2(10, 0))
	_check(absf(north) < 0.001, "north bearing is %s" % north)
	_check(absf(east - PI * 0.5) < 0.001, "east bearing is %s" % east)
	var across: float = FirstExitBearings.relative_bearing(deg_to_rad(359.0), deg_to_rad(1.0))
	_check(absf(across - deg_to_rad(2.0)) < 0.02, "359 to 1 wrapped to %s deg" % rad_to_deg(across))


func _check_slot() -> void:
	var ahead: Dictionary = FirstExitBearings.marker_slot(0.0)
	_check(bool(ahead["on_strip"]) and absf(float(ahead["u"])) < 0.001, "ahead marker left the center")
	var edge: Dictionary = FirstExitBearings.marker_slot(deg_to_rad(50.0))
	_check(bool(edge["on_strip"]), "the 50 degree edge fell off the tape")
	var past: Dictionary = FirstExitBearings.marker_slot(deg_to_rad(51.0))
	_check(not bool(past["on_strip"]) and int(past["edge"]) == 1, "just outside 50 degrees did not pin right")
	var behind: Dictionary = FirstExitBearings.marker_slot(deg_to_rad(-120.0))
	_check(not bool(behind["on_strip"]) and int(behind["edge"]) == -1, "a target behind did not pin left")


func _check_camera() -> void:
	var camera := Camera3D.new()
	root.add_child(camera)
	_check(absf(FirstExitBearings.camera_bearing(camera)) < 0.001, "an unturned camera is not looking north")
	camera.rotation.y = PI * 0.5
	_check(absf(wrapf(FirstExitBearings.camera_bearing(camera) + PI * 0.5, -PI, PI)) < 0.001,
		"yaw 90 is not west, got %s" % FirstExitBearings.camera_bearing(camera))
	camera.free()


func _check_catalog() -> void:
	var bearings := FirstExitBearings.new()
	_check(bearings.shelter_id() == "kw:building:osm:w339414849", "shelter id %s" % bearings.shelter_id())
	var xz: Vector2 = bearings.shelter_xz()
	_check(xz.distance_to(Vector2(-3538.75, 1594.38)) < 0.01, "bearing point is %s, not the entrance" % xz)
	_check(xz.distance_to(Vector2(-3531.78, 1590.28)) > 5.0, "bearing point fell back to the footprint centroid")
	bearings.free()


func _check_lifecycle() -> void:
	var armed := FirstExitBearings.new()
	armed.begin_play(true)
	var place: String = armed.shelter_id()
	_check(armed.active_target_id == place and armed.intro_assigned, "scenario start did not arm 727")
	armed.recall()
	_check(armed.active_target_id == "", "recall did not clear the armed mark")
	armed.recall()
	_check(armed.active_target_id == place, "recall did not restore the known house")
	armed.free()
	var shelter_boot := FirstExitBearings.new()
	shelter_boot.begin_play(false)
	_check(shelter_boot.active_target_id == "" and shelter_boot.intro_assigned and shelter_boot.is_known(place),
		"a non-scenario boot armed a mission mark")
	shelter_boot.free()


func _check_zones() -> void:
	var bearings := FirstExitBearings.new()
	bearings.begin_play(true)
	var place: String = bearings.shelter_id()
	var other := ThermalZone.new()
	bearings.note_zones([other])
	_check(not bearings.is_visited(place) and bearings.active_target_id == place, "a foreign interior counted as 727")
	other.free()
	var shelter := KeyWest727Shelter.new()
	var zone := ThermalZone.new()
	shelter.add_child(zone)
	bearings.note_zones([zone])
	_check(bearings.is_visited(place) and bearings.is_known(place), "entering 727 did not record the visit")
	_check(bearings.active_target_id == "", "entering 727 left the mark up")
	bearings.note_zones([])
	_check(bearings.active_target_id == "", "leaving 727 restored the mark")
	bearings.recall()
	_check(bearings.active_target_id == place, "recall after the visit did nothing")
	bearings.note_zones([])
	_check(bearings.active_target_id == place, "standing outside cleared a manual mark")
	bearings.note_zones([zone])
	_check(bearings.active_target_id == "", "re-entering 727 left a manual mark up")
	zone.free()
	shelter.free()
	bearings.free()


func _check_save() -> void:
	var place: String = FirstExitBearings.new().shelter_id()
	var lived := FirstExitBearings.new()
	lived.begin_play(true)
	var zones: Array = _house_zone()
	lived.note_zones(zones)
	var house: Node = (zones[0] as Node).get_parent()
	var data: Dictionary = lived.get_save_data()
	lived.free()
	house.free()
	var restored := FirstExitBearings.new()
	restored.load_save_data(data)
	_check(restored.is_visited(place) and restored.is_known(place), "visit did not survive the save")
	_check(restored.active_target_id == "" and restored.intro_assigned, "reload re-armed 727")
	restored.free()
	var legacy := FirstExitBearings.new()
	legacy.begin_play(true)
	legacy.on_loaded_payload({})
	_check(legacy.active_target_id == "" and legacy.intro_assigned and legacy.is_known(place),
		"a save without this key grew a new mission mark")
	legacy.free()
	var kept := FirstExitBearings.new()
	kept.begin_play(true)
	kept.on_loaded_payload({"first_exit_bearings": {}})
	_check(kept.active_target_id == place, "a present save key was treated as absent")
	kept.free()
	var dirty := FirstExitBearings.new()
	dirty.load_save_data({
		"known": [],
		"visited": [place],
		"active_target_id": "not-a-place",
		"intro_assigned": false,
	})
	_check(dirty.is_known(place) and dirty.is_visited(place), "visited did not imply known")
	_check(dirty.active_target_id == "" and dirty.intro_assigned, "an unknown target or a spent intro came back")
	dirty.free()


func _house_zone() -> Array:
	var shelter := KeyWest727Shelter.new()
	var zone := ThermalZone.new()
	shelter.add_child(zone)
	return [zone]


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("first exit bearings: %s" % message)
