extends SceneTree

## The "camera behind Henry" key on the direct rig: the view turns to where he faces, by the short way, and
## stops there; mouse motion during the turn takes the view back at once; without the key nothing recentres.
## Run: godot --headless --script tests/systems/test_tps_camera_behind.gd

const FACING_DEG: float = 150.0

var _failures: int = 0
var _frame: int = 0
var _camera: TpsCamera
var _player: CharacterBody3D
var _cancel_yaw: float = 0.0


func _physics_process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		1:
			_build()
		120:
			## Two seconds facing away from the view and no key: nothing turned.
			_check(absf(rad_to_deg(_camera.get_yaw())) < 0.01, "the view recentred by itself to %.1f deg" % rad_to_deg(_camera.get_yaw()))
			_press()
		126:
			var turned: float = rad_to_deg(_camera.get_yaw())
			_check(turned > 5.0 and turned < FACING_DEG - 5.0, "six frames into the turn the view is at %.1f deg: not an eased turn" % turned)
		240:
			_check(absf(rad_to_deg(angle_difference(_camera.get_yaw(), deg_to_rad(FACING_DEG)))) < 0.5,
				"the key left the view at %.1f deg, Henry faces %.1f" % [rad_to_deg(_camera.get_yaw()), FACING_DEG])
			_check(absf(_camera.get_view_pitch_deg() - _camera.behind_pitch_deg) < 0.5, "the key left the pitch at %.1f" % _camera.get_view_pitch_deg())
			_camera.set_look(0.0, -30.0)
			_press()
		246:
			_mouse(4.0)
		248:
			_cancel_yaw = _camera.get_yaw()
		330:
			_check(absf(rad_to_deg(angle_difference(_camera.get_yaw(), _cancel_yaw))) < 0.01,
				"after the mouse moved the key's turn went on by %.1f deg" % rad_to_deg(angle_difference(_cancel_yaw, _camera.get_yaw())))
			_finish()
	return false


func _build() -> void:
	_player = CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	shape.position.y = 1.0
	_player.add_child(shape)
	_player.rotation.y = deg_to_rad(FACING_DEG)
	root.add_child(_player)
	_camera = TpsCamera.new()
	_camera.player = _player
	_camera.origin_above_feet = 0.0
	root.add_child(_camera)
	_camera.set_look(0.0, -30.0)


func _press() -> void:
	var event := InputEventAction.new()
	event.action = &"camera_behind"
	event.pressed = true
	Input.parse_input_event(event)


func _mouse(dx: float) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = Vector2(dx, 0.0)
	event.screen_relative = Vector2(dx, 0.0)
	Input.parse_input_event(event)


func _finish() -> void:
	if _failures > 0:
		push_error("tps camera behind: %d check(s) failed" % _failures)
		quit(1)
		return
	print("tps camera behind: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("tps camera behind: %s" % message)
