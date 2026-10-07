extends SceneTree

## Scripted walks (move_to_position, used by interaction approaches and the door
## step-out) stop on their target at production and data-matched braking rates.
## Run: godot --headless --script tests/systems/test_scripted_walk_braking.gd

## Farthest a scripted walk may come to rest past or short of its target, metres.
const TOLERANCE_M: float = 0.06
## [label, acceleration, deceleration] in m/s^2; production and data-matched body.
const PROFILES: Array = [["production", 12.0, 18.0], ["data-matched", 3.0, 3.5]]
const DISTANCES: Array[float] = [0.3, 3.0]

var _failures: int = 0
var _player: Player
var _stopped: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	root.add_child(floor_body)
	_player = (load("res://scenes/actors/player/player.tscn") as PackedScene).instantiate() as Player
	root.add_child(_player)
	_player.movement_stopped.connect(func() -> void: _stopped = true)
	for profile: Array in PROFILES:
		var scale: float = maxf(_player.movement.walk_speed, 1.0)
		_player.movement.accel_rate = float(profile[1]) / scale
		_player.movement.decel_rate = float(profile[2]) / scale
		for distance: float in DISTANCES:
			await _walk(String(profile[0]), distance)
	if _failures > 0:
		push_error("scripted walk braking: %d check(s) failed" % _failures)
		quit(1)
		return
	print("scripted walk braking: all checks passed")
	quit(0)


func _walk(label: String, distance: float) -> void:
	_player.global_position = Vector3(0.0, 1.0, 0.0)
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	for _i: int in range(30):
		await physics_frame
	var start: Vector3 = _player.global_position
	var forward: Vector3 = -_player.global_transform.basis.z
	forward = Vector3(forward.x, 0.0, forward.z).normalized()
	var target: Vector3 = start + forward * distance
	_stopped = false
	_player.move_to_position(target)
	var ticks: int = 0
	while not _stopped and ticks < 600:
		await physics_frame
		ticks += 1
	for _i: int in range(60):
		await physics_frame
	var rest: float = (_player.global_position - target).dot(forward)
	var note: String = "%s %.1f m: rest %+.3f m from target after %.2f s" % [label, distance, rest, ticks / 60.0]
	print("scripted walk braking: " + note)
	_check(_stopped, "%s: movement_stopped never fired" % note)
	_check(absf(rest) <= TOLERANCE_M, "%s: outside +-%.2f m" % [note, TOLERANCE_M])


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("scripted walk braking: " + message)
