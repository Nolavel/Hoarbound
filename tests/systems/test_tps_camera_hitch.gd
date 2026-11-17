extends SceneTree

## A hitched frame while aiming a throw (right mouse with a stone in hand): the aim spring is stepped
## explicitly, and one 100 ms frame used to blow it up and throw the camera out of the world.
## Frames of 100 and 250 ms with the aim held must leave the camera on its boom.
## Run: godot --headless --script tests/systems/test_tps_camera_hitch.gd


class Aimer extends RefCounted:
	func weight() -> float:
		return 1.0


var _failures: int = 0
var _frame: int = 0
var _camera: TpsCamera
var _player: CharacterBody3D
var _aimer := Aimer.new()


func _physics_process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_player = CharacterBody3D.new()
		var shape := CollisionShape3D.new()
		shape.shape = CapsuleShape3D.new()
		shape.position.y = 1.0
		_player.add_child(shape)
		root.add_child(_player)
		AimIntentCapability.publish(_player, _aimer, &"weight")
		_camera = TpsCamera.new()
		_camera.player = _player
		_camera.origin_above_feet = 0.0
		root.add_child(_camera)
		_camera.set_look(0.0, -10.0)
	elif _frame == 30:
		for hitch: float in [0.1, 0.1, 0.25, 0.1, 0.016, 0.1, 0.25]:
			_camera._process(hitch)
			var distance: float = _camera.global_position.distance_to(_camera.get_eye_position())
			_check(is_finite(distance) and distance < _camera.far_distance * 1.3,
				"after a %.0f ms frame with the aim held the camera is %.1f m from Henry" % [hitch * 1000.0, distance])
		_finish()
	return false


func _finish() -> void:
	if _failures > 0:
		push_error("tps camera hitch: %d check(s) failed" % _failures)
		quit(1)
		return
	print("tps camera hitch: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("tps camera hitch: %s" % message)
