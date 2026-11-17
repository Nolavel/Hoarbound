extends SceneTree

## The look stick: a dead zone with no drift, a curve that is fine near the centre and reaches full speed
## at the rim, a diagonal no faster than an axis, a rim ramp that builds and resets, and the stick turning
## the direct camera at that speed without touching the mouse's sensitivity.
## Run: godot --headless --script tests/systems/test_stick_look.gd

const STEP: float = 1.0 / 60.0

var _failures: int = 0
var _frame: int = 0
var _camera: TpsCamera
var _start_yaw: float = 0.0


func _initialize() -> void:
	_check_curve()


func _physics_process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		1:
			_build()
		30:
			_start_yaw = _camera.get_yaw()
			Input.action_press(&"look_right", 0.5)
		90:
			Input.action_release(&"look_right")
			var stick: StickLook = (root.get_node(^"InputSystems") as Node).call(&"get_stick_look")
			var want: float = rad_to_deg(stick.update(Vector2(0.5, 0.0), 0.0).x)
			var turned: float = -rad_to_deg(angle_difference(_start_yaw, _camera.get_yaw()))
			_check(absf(turned - want) < want * 0.15, "half stick for a second turned the view %.1f deg, the curve says %.1f" % [turned, want])
			_start_yaw = _camera.get_yaw()
		150:
			_check(absf(rad_to_deg(angle_difference(_start_yaw, _camera.get_yaw()))) < 0.01, "the view drifts with the stick at rest")
			_finish()
	return false


func _check_curve() -> void:
	var stick := StickLook.new()
	_check(stick.update(Vector2(0.1, 0.05), STEP) == Vector2.ZERO, "the stick turns inside its dead zone")
	var slow: float = stick.update(Vector2(0.3, 0.0), STEP).x
	var half: float = stick.update(Vector2(0.55, 0.0), STEP).x
	var full: float = stick.update(Vector2(1.0, 0.0), STEP).x
	_check(slow > 0.0 and slow < half and half < full, "the curve is not rising: %.2f, %.2f, %.2f" % [slow, half, full])
	_check(slow < full * 0.1, "a light touch turns at %.0f %% of full speed: no fine aim" % (slow / full * 100.0))
	_check(is_equal_approx(full, deg_to_rad(stick.yaw_speed_deg)), "full stick turns at %.0f deg/s, not %.0f" % [rad_to_deg(full), stick.yaw_speed_deg])
	stick.reset()
	var diagonal: Vector2 = stick.update(Vector2(1.0, 1.0), STEP)
	_check(diagonal.x <= full + 1e-4, "a diagonal turns faster in yaw than a full sideways push")
	stick.reset()
	var ramped: float = 0.0
	for i: int in range(90):
		ramped = stick.update(Vector2(1.0, 0.0), STEP).x
	_check(is_equal_approx(ramped, full * (1.0 + stick.ramp_boost)), "held at the rim 1.5 s the turn is %.2f of full, not %.2f" % [ramped / full, 1.0 + stick.ramp_boost])
	stick.update(Vector2(0.5, 0.0), STEP)
	_check(is_equal_approx(stick.update(Vector2(1.0, 0.0), STEP).x, full), "the rim ramp did not reset when the stick came off the rim")


func _build() -> void:
	var player := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	shape.position.y = 1.0
	player.add_child(shape)
	root.add_child(player)
	_camera = TpsCamera.new()
	_camera.player = player
	_camera.origin_above_feet = 0.0
	root.add_child(_camera)
	_camera.set_look(0.0, -10.0)


func _finish() -> void:
	if _failures > 0:
		push_error("stick look: %d check(s) failed" % _failures)
		quit(1)
		return
	print("stick look: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("stick look: %s" % message)
