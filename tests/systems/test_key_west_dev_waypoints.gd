extends SceneTree

## Debug waypoints: the target list holds the First Exit route goals and the listed addresses, F5 cycles through
## them and back to off, and F6 puts Henry on the target.
## Run: godot --headless --script tests/systems/test_key_west_dev_waypoints.gd

var _failures: int = 0


func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	var player: CharacterBody3D = CharacterBody3D.new()
	root.add_child(player)
	var waypoints: KeyWestDevWaypoints = KeyWestDevWaypoints.new()
	root.add_child(waypoints)
	var context: WorldContext = WorldContext.new()
	context.player = player
	waypoints.on_world_ready(context)
	var names: PackedStringArray = waypoints.target_names()
	_check(names.has("727_fort_st_entrance") and names.has("duval_x_front"), "route goals missing: %s" % [names])
	_check(names.size() == 9, "expected 7 distinct route goals and 2 addresses, got %d: %s" % [names.size(), names])
	var address: bool = false
	for n: String in names:
		address = address or n.to_upper().contains("727 FORT ST")
	_check(address, "the 727 Fort St address did not resolve: %s" % [names])
	for i: int in range(names.size()):
		waypoints.next_target()
		_check(waypoints.current_target().get("name", "") == names[i], "F5 step %d did not select %s" % [i, names[i]])
	waypoints.next_target()
	_check(waypoints.current_target().is_empty(), "F5 after the last target did not switch the marker off")
	waypoints.next_target()
	waypoints.teleport()
	var at: Vector3 = waypoints.current_target()["at"]
	_check(Vector2(player.global_position.x, player.global_position.z).distance_to(Vector2(at.x, at.z)) < 0.01, "F6 did not move Henry to the target")
	waypoints.free()
	player.free()
	if _failures > 0:
		push_error("dev waypoints: %d check(s) failed" % _failures)
		quit(1)
		return
	print("dev waypoints: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("dev waypoints: %s" % message)
