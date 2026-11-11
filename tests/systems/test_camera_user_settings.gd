extends SceneTree

## Player camera settings: the store clamps and round-trips them, the direct camera applies field of view,
## distance, default shoulder and stick sensitivity on reload without stacking, and the Settings panel
## stages and saves them. Camera values go to its own file, never the player's.
## Run: godot --headless --script tests/systems/test_camera_user_settings.gd

const PATH: String = "user://test_camera_settings.cfg"

var _failures: int = 0
var _frame: int = 0
var _camera: TpsCamera
var _base_fov: float = 0.0
var _base_distance: float = 0.0


func _initialize() -> void:
	CameraUserSettings.config_path = PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	var defaults: Dictionary = CameraUserSettings.load_camera()
	_check(is_zero_approx(float(defaults["fov_offset_deg"])) and is_equal_approx(float(defaults["distance_scale"]), 1.0)
		and not bool(defaults["left_shoulder"]), "defaults are not neutral: %s" % defaults)
	CameraUserSettings.save_values({"fov_offset_deg": 90.0, "distance_scale": 0.1, "mouse_sensitivity_multiplier": 1.5})
	var clamped: Dictionary = CameraUserSettings.load_camera()
	_check(is_equal_approx(float(clamped["fov_offset_deg"]), 15.0) and is_equal_approx(float(clamped["distance_scale"]), 0.75),
		"out-of-range values were stored: %s" % clamped)
	CameraUserSettings.save_camera(0.5, true)
	var kept: Dictionary = CameraUserSettings.load_camera()
	_check(is_equal_approx(float(kept["fov_offset_deg"]), 15.0) and bool(kept["invert_y"]), "the old two-value save dropped other keys: %s" % kept)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func _physics_process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		1:
			_build()
		120:
			_base_fov = _camera.fov
			_base_distance = _camera.global_position.distance_to(_camera.get_eye_position())
			_check(_camera.global_position.x > 0.2, "by default the camera is not over the right shoulder")
			CameraUserSettings.save_values({"fov_offset_deg": 10.0, "distance_scale": 0.8, "left_shoulder": true})
			_camera.reload_user_settings()
			_camera.reload_user_settings()
		300:
			_check(absf(_camera.fov - (_base_fov + 10.0)) < 0.01, "field of view %.1f after +10, from %.1f" % [_camera.fov, _base_fov])
			var distance: float = _camera.global_position.distance_to(_camera.get_eye_position())
			_check(absf(distance / _base_distance - 0.8) < 0.06, "distance %.2f m after 80 %%, from %.2f" % [distance, _base_distance])
			_check(_camera.global_position.x < -0.2, "the left-shoulder default left the camera at x=%.2f" % _camera.global_position.x)
			_check_panel()
			_finish()
	return false


func _check_panel() -> void:
	var panel := CameraSettingsPanel.new()
	root.add_child(panel)
	panel.open()
	var slider := panel.find_child("FovOffsetDegSlider", true, false) as HSlider
	var accept := panel.find_child("AcceptButton", true, false) as Button
	var shoulder := panel.find_child("LeftShoulder", true, false) as CheckBox
	if slider == null or accept == null or shoulder == null:
		_check(false, "the panel has no field-of-view slider, left-shoulder box or Accept button")
		return
	_check(is_equal_approx(slider.value, 10.0) and shoulder.button_pressed, "the panel opened without the stored values")
	_check(accept.disabled, "Accept is live with nothing changed")
	slider.value = -5.0
	_check(not accept.disabled, "Accept stayed off after the slider moved")
	accept.pressed.emit()
	_check(is_equal_approx(float(CameraUserSettings.load_camera()["fov_offset_deg"]), -5.0), "Accept did not store the field of view")
	_check(absf(_camera.fov - (_base_fov - 5.0)) < 0.01, "Accept did not reach the camera: fov %.1f" % _camera.fov)


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
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	CameraUserSettings.config_path = CameraUserSettings.CONFIG_PATH
	if _failures > 0:
		push_error("camera user settings: %d check(s) failed" % _failures)
		quit(1)
		return
	print("camera user settings: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("camera user settings: %s" % message)
