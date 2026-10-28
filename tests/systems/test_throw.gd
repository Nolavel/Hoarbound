extends SceneTree

## Throwing (#257 stage 2): the aim solve lands on its target, a thrown stone comes to rest as
## a pickup, and a snowball strikes a target through ThrowImpactCapability and is gone.
## Run: godot --headless --script tests/systems/test_throw.gd

var _failures: int = 0
var _hits: Array = []


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame  # the root joins the tree after _initialize
	_check_solve()
	var floor := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	floor_shape.shape = box
	floor.add_child(floor_shape)
	floor.position = Vector3(0.0, -0.5, 0.0)
	root.add_child(floor)

	var stone: ThrownItem = ThrownItem.launch(&"stone", Vector3(0.0, 1.5, 0.0), Vector3(0.0, 2.0, -6.0), null, root)
	for _i: int in range(600):
		await physics_frame
		if not is_instance_valid(stone):
			break
	var pickups: Array[Node] = root.find_children("*", "ItemPickup", true, false)
	_check(not is_instance_valid(stone), "the thrown stone never came to rest")
	_check(pickups.size() == 1 and (pickups[0] as ItemPickup).item_id == &"stone", "the stone did not become a pickup: %s" % [pickups])
	if pickups.size() == 1:
		_check((pickups[0] as Node3D).global_position.z < -1.0, "the stone did not fly forward")

	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(4.0, 4.0, 0.2)
	wall_shape.shape = slab
	wall.add_child(wall_shape)
	wall.position = Vector3(0.0, 2.0, -5.0)
	root.add_child(wall)
	ThrowImpactCapability.publish(wall, self, &"_on_wall_hit")
	var snowball: ThrownItem = ThrownItem.launch(&"snow_handful", Vector3(0.0, 2.0, 0.0), Vector3(0.0, 1.0, -12.0), null, root)
	for _i: int in range(120):
		await physics_frame
		if not is_instance_valid(snowball):
			break
	_check(_hits.size() == 1 and _hits[0][0] == &"snow_handful", "the wall was not struck once by the snowball: %s" % [_hits])
	if _hits.size() == 1:
		_check(absf((_hits[0][1] as Vector3).z + 4.9) < 0.15, "the hit point is off the wall face: %s" % [_hits[0][1]])
		_check(float(_hits[0][3]) > 1.0, "the snowball's impulse is implausibly small: %.2f" % float(_hits[0][3]))
	_check(not is_instance_valid(snowball), "the snowball outlived its hit")

	print("test_throw: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _on_wall_hit(item_id: StringName, point: Vector3, normal: Vector3, impulse: float, _collider: Object) -> bool:
	_hits.append([item_id, point, normal, impulse])
	return true


## The low-arc solve, flown as a parabola, passes through its target; out of reach it lobs at 45 deg.
func _check_solve() -> void:
	var from := Vector3(0.0, 1.6, 0.0)
	for target: Vector3 in [Vector3(8.0, 1.0, -6.0), Vector3(0.0, 4.0, -12.0), Vector3(-3.0, 0.0, 2.0)]:
		var speed: float = 13.0
		var velocity: Vector3 = ThrowComponent.launch_direction(from, target, speed, 9.8) * speed
		var flat: float = Vector2(target.x - from.x, target.z - from.z).length()
		var t: float = flat / Vector2(velocity.x, velocity.z).length()
		var at: Vector3 = from + velocity * t + Vector3.DOWN * 4.9 * t * t
		_check(at.distance_to(target) < 0.05, "the solve misses %s by %.3f m" % [target, at.distance_to(target)])
	var lob: Vector3 = ThrowComponent.launch_direction(from, Vector3(0.0, 0.0, -100.0), 10.0, 9.8)
	_check(absf(rad_to_deg(asin(lob.y)) - 45.0) < 0.5, "an out-of-reach target is not lobbed at 45 degrees")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
