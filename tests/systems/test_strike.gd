extends SceneTree

## The frying pan swung: LMB a quick strike, RMB held then released a heavier one. A crate ahead takes both
## (an impulse along Henry's facing), the held strike harder; the pan rides the closed fist through the swing.
## Run: godot --headless --path . --fixed-fps 30 --script res://tests/systems/test_strike.gd

var _failures: int = 0
var _impulses: Array[float] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	var floor := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = WorldBoundaryShape3D.new()
	floor.add_child(floor_shape)
	root.add_child(floor)
	var player := (load("res://scenes/actors/player/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	root.add_child(player)
	player.global_position = Vector3(0.0, 1.0, 0.0)
	for _i: int in range(30):
		await physics_frame
	var held := player.get_node(^"HeldItemComponent") as HeldItemComponent
	var strike := player.get_node(^"StrikeComponent") as StrikeComponent
	strike.struck.connect(func(impulse: float, hits: int) -> void: _impulses.append(impulse if hits > 0 else 0.0))
	_check(held.present_owned(&"frying_pan"), "the pan on the carabiner could not be taken in hand")
	_check(strike.held_strike_impulse() > 0.0, "the pan in hand is not a striking tool")
	for _i: int in range(20):
		await process_frame
	var visual := player.get_node(^"HenryUALVisual") as HenryUALAnimation
	var grip: HandGrip = visual.get_hand_grip(visual.get_held_prop() == held.get_held_prop())
	var pan: Node3D = held.get_held_prop()
	var grip_point: Vector3 = pan.global_transform * HeldItemComponent.PAN_GRIP_POINT
	_check(grip_point.distance_to(grip.handle_centre) < 0.01, "the pan's handle is not in the fist")
	## A crate standing in reach ahead.
	var crate := _crate(player)
	_press(strike, &"fire", true)
	_press(strike, &"fire", false)
	_check(strike.is_striking(), "LMB did not start a strike")
	for _i: int in range(40):
		await physics_frame
	_check(_impulses.size() == 1 and _impulses[0] > 0.0, "the quick strike did not land on the crate")
	_check(crate.linear_velocity.dot(-player.global_basis.z) > 0.1, "the crate was not knocked away from Henry")
	for _i: int in range(30):
		await physics_frame
	crate.free()
	var crate2 := _crate(player)
	_press(strike, &"present_held", true)
	for _i: int in range(45):
		await physics_frame
	_check(strike.is_striking() and _impulses.size() == 1, "the held wind-up struck before RMB was released")
	_press(strike, &"present_held", false)
	for _i: int in range(30):
		await physics_frame
	_check(_impulses.size() == 2 and _impulses[1] > 0.0, "the released heavy strike did not land")
	if _impulses.size() == 2:
		_check(_impulses[1] > _impulses[0], "the held strike was not harder than the quick one (%.1f vs %.1f)" % [_impulses[1], _impulses[0]])
	crate2.queue_free()
	print("strike: %s" % ("all checks passed" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _crate(player: Node3D) -> RigidBody3D:
	var crate := RigidBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 1.8, 0.6)
	shape.shape = box
	crate.add_child(shape)
	crate.mass = 2.0
	## Placed before it enters the world: added at the origin first it would shove Henry aside for a step.
	crate.position = Vector3(player.global_position.x, 0.9, player.global_position.z) + (-player.global_basis.z) * 0.95
	root.add_child(crate)
	return crate


func _press(strike: StrikeComponent, action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	strike._input(event)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("strike: %s" % message)
