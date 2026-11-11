extends SceneTree

## StepStairs: the real Henry walks up a flight of ten 0.17 x 0.28 m steps and back down without leaving the
## ground, cannot pass through the flight from the side, and bare box steps of the same size still stop him
## (the reason the component exists). A flight steeper than he walks warns its author.
## Run: godot --headless --script tests/systems/test_step_stairs.gd

var _failures: int = 0
var _player: Player
var _camera: TpsCamera
var _world: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	_box(Vector3(0.0, -0.5, 0.0), Vector3(60.0, 1.0, 60.0))
	var stairs := StepStairs.new()
	stairs.position = Vector3(0.0, 0.0, -2.0)
	_world.add_child(stairs)
	## The landing the flight leads to.
	_box(Vector3(0.0, stairs.get_rise() * 0.5, -2.0 - stairs.get_run() - 2.0), Vector3(1.2, stairs.get_rise(), 4.0))
	_check(stairs.get_child_count(false) == 0, "the generated nodes would be saved with the scene: they must be internal")
	_check(stairs.get_child_count(true) == 2, "StepStairs built %d internal nodes, not a wedge and a mesh" % stairs.get_child_count(true))
	_check(stairs._get_configuration_warnings().is_empty(), "a 31 degree flight warns: %s" % stairs._get_configuration_warnings())
	_player = (load("res://scenes/actors/player/player.tscn") as PackedScene).instantiate() as Player
	root.add_child(_player)
	_camera = (load("res://scenes/game/systems/camera/tps_camera.tscn") as PackedScene).instantiate() as TpsCamera
	_camera.player = _player
	root.add_child(_camera)
	var feet: float = await _feet_offset()

	await _place(Vector3(0.0, 1.0, 0.0), 0.0)
	var airborne: int = await _walk(func() -> bool: return _player.global_position.z < -2.0 - stairs.get_run() - 1.0)
	var top: float = _player.global_position.y - feet
	_check(absf(top - stairs.get_rise()) < 0.05, "up: Henry stands %.2f m up, the flight rises %.2f" % [top, stairs.get_rise()])
	_check(airborne < 6, "up: Henry was off the ground in %d ticks" % airborne)

	await _place(_player.global_position, PI)
	airborne = await _walk(func() -> bool: return _player.global_position.z > -0.5)
	_check(absf(_player.global_position.y - feet) < 0.05, "down: Henry ended %.2f m over the ground" % (_player.global_position.y - feet))
	_check(airborne < 6, "down: Henry left the steps for %d ticks; he must walk them, not fall" % airborne)

	## From the side, halfway up the flight: the wedge is solid to the ground.
	await _place(Vector3(3.0, 1.0, -2.0 - stairs.get_run() * 0.7), PI * 0.5)
	await _walk(func() -> bool: return _player.global_position.x < -3.0)
	_check(_player.global_position.x > 0.6, "side: Henry walked through the flight to x=%.2f" % _player.global_position.x)

	## Bare box steps, well away from the flight: he does not climb them.
	for i: int in range(6):
		var height: float = 0.17 * float(i + 1)
		_box(Vector3(10.0, height * 0.5, -2.0 - 0.28 * (float(i) + 0.5)), Vector3(1.2, height, 0.28))
	await _place(Vector3(10.0, 1.0, 0.0), 0.0)
	await _walk(func() -> bool: return _player.global_position.z < -4.0)
	_check(_player.global_position.y - feet < 0.1, "bare box steps now carry Henry up (%.2f m): StepStairs' premise changed" % (_player.global_position.y - feet))

	var steep := StepStairs.new()
	steep.riser = 0.35
	steep.tread = 0.25
	steep.position = Vector3(-10.0, 0.0, 0.0)
	_world.add_child(steep)
	_check(not steep._get_configuration_warnings().is_empty(), "a 54 degree flight does not warn its author")

	if _failures > 0:
		push_error("step stairs: %d check(s) failed" % _failures)
		quit(1)
		return
	print("step stairs: all checks passed")
	quit(0)


## Height of Henry's origin over the ground he stands on.
func _feet_offset() -> float:
	await _place(Vector3(5.0, 1.0, 5.0), 0.0)
	return _player.global_position.y


## Holds W for up to 12 s or until `done`; returns the ticks Henry was off the floor.
func _walk(done: Callable) -> int:
	var airborne: int = 0
	Input.action_press(&"move_forward")
	for i: int in range(720):
		await physics_frame
		airborne += int(not _player.is_on_floor())
		if done.call():
			break
	Input.action_release(&"move_forward")
	for i: int in range(20):
		await physics_frame
	return airborne


func _place(at: Vector3, yaw: float) -> void:
	Input.action_release(&"move_forward")
	_player.global_position = at
	_player.velocity = Vector3.ZERO
	_player.rotation.y = yaw
	_player.reset_physics_interpolation()
	_camera.set_look(yaw, -10.0)
	_camera.snap_to_target()
	for i: int in range(60):
		await physics_frame


func _box(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	_world.add_child(body)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("step stairs: %s" % message)
