extends SceneTree

## A ground-drift streamer sweeps downwind along a shallow arc and only starts when the whole sweep
## is on screen. Run: godot --headless --script tests/systems/test_snow_lift_sweep.gd

const WIND_MPS: float = 12.0

var _failures: int = 0
var _started: bool = false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	stage.add_child(ground)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(0.0, 1.7, 8.0)
	camera.make_current()
	var lift := SnowLift.new()
	stage.add_child(lift)
	await physics_frame
	await physics_frame

	var along := Vector3.RIGHT
	var length: float = SnowLift.sweep_length(WIND_MPS)
	_check(length > 6.0, "a 12 m/s sweep is shorter than the old 5 m patch: %.1f m" % length)
	_check(not lift.launch_through(Vector3(0.0, 0.0, 30.0), along, WIND_MPS, 1.0, camera),
		"a sweep behind the camera started")
	_check(lift.launch_through(Vector3(0.0, 0.0, -14.0), along, WIND_MPS, 1.0, camera),
		"a sweep in front of the camera did not start")
	var start: Vector3 = lift.global_position
	var widest: float = 0.0
	var steps: int = 0
	while lift.is_physics_processing() and steps < 600:
		await physics_frame
		steps += 1
		widest = maxf(widest, absf(lift.global_position.z - start.z))
		_check(absf(lift.global_position.y - start.y) < 0.01, "the head left the ground")
	var travelled: float = lift.global_position.x - start.x
	_check(travelled > length * 0.8, "the head did not travel downwind: %.1f of %.1f m" % [travelled, length])
	_check(widest > 0.2 and widest < length * 0.15, "the path is not a shallow arc: bow %.2f m" % widest)
	_check(lift.is_active(), "the trail ended with the sweep")
	stage.queue_free()
	print("snow lift sweep: all checks passed" if _failures == 0 else "snow lift sweep: %d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error(message)
