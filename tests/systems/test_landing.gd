extends SceneTree

## Henry's airtime and landings: a walk start stays on the floor, a 0.3 m step-down
## keeps walking, a standing jump lands with the full clip, a moving one hands back.
## Run: godot --headless --script tests/systems/test_landing.gd

const AIR_STATES: Array[StringName] = [&"JumpStart", &"AirLoop", &"Land", &"LandMoving"]

var _failures: int = 0
var _player: Player
var _visual: HenryUALAnimation
## Base states seen since the last _watch() reset, in order of first appearance.
var _seen: Array[StringName] = []
var _left_floor: bool = false
var _landed_tick: int = -1
var _grounded_tick: int = -1
var _tick: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_box(Vector3(10.0, 1.0, 40.0), Vector3(0.0, -0.5, 0.0))
	_box(Vector3(10.0, 1.0, 20.0), Vector3(0.0, -0.8, -30.0))
	_player = (load("res://scenes/actors/player/player.tscn") as PackedScene).instantiate() as Player
	root.add_child(_player)
	_visual = _player.animation_component
	_player.global_position = Vector3(0.0, 1.0, -12.0)
	_player.rotation = Vector3.ZERO
	_player.reset_physics_interpolation()
	physics_frame.connect(_on_tick)
	await _ticks(60)

	_watch()
	Input.action_press(&"move_forward")
	await _ticks(60)
	_check(not _left_floor, "a walk start lifts Henry off the floor")
	_check(not _any_air_state(), "a walk start plays %s" % [_seen])

	# Walk on to the 0.3 m step-down at z = -20.
	while _player.global_position.z > -19.0:
		await _ticks(1)
	_watch()
	await _ticks(90)
	_check(_left_floor, "the step-down never left the floor (test setup)")
	_check(not _seen.has(&"Land") and not _seen.has(&"LandMoving"), "a 0.3 m step-down plays a landing: %s" % [_seen])
	_check(_visual._state_playback.get_current_node() == &"Grounded", "the step-down does not walk on")

	await _jump()
	_check(_seen.has(&"LandMoving") and not _seen.has(&"Land"), "a moving jump lands with %s" % [_seen])
	_check(_back_to_grounded_within(_visual.moving_landing_seconds + 0.4), "a moving landing holds the walk back")

	Input.action_release(&"move_forward")
	await _ticks(90)
	await _jump()
	_check(_seen.has(&"JumpStart") and _seen.has(&"Land"), "a standing jump lands with %s" % [_seen])
	_check(_back_to_grounded_within(1.6), "the standing landing never returns to Grounded")

	if _failures > 0:
		push_error("landing: %d check(s) failed" % _failures)
		quit(1)
		return
	print("landing: all checks passed")
	quit(0)


func _jump() -> void:
	_watch()
	Input.action_press(&"jump")
	await _ticks(4)
	Input.action_release(&"jump")
	await _ticks(150)


func _watch() -> void:
	_seen.clear()
	_left_floor = false
	_landed_tick = -1
	_grounded_tick = -1


func _on_tick() -> void:
	_tick += 1
	var node: StringName = _visual._state_playback.get_current_node()
	if not _seen.has(node):
		_seen.append(node)
	if not _player.is_on_floor():
		_left_floor = true
	elif _left_floor and _landed_tick < 0:
		_landed_tick = _tick
	if _landed_tick >= 0 and _grounded_tick < 0 and node == &"Grounded":
		_grounded_tick = _tick


func _back_to_grounded_within(seconds: float) -> bool:
	var physics_hz: float = float(Engine.physics_ticks_per_second)
	print("landing: touch-down to Grounded %.2f s (limit %.2f s)" % [(_grounded_tick - _landed_tick) / physics_hz, seconds])
	return _landed_tick >= 0 and _grounded_tick >= 0 and (_grounded_tick - _landed_tick) / physics_hz <= seconds


func _any_air_state() -> bool:
	for state: StringName in AIR_STATES:
		if _seen.has(state):
			return true
	return false


func _ticks(count: int) -> void:
	for _i: int in range(count):
		await physics_frame


func _box(size: Vector3, center: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	root.add_child(body)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("landing: " + message)
