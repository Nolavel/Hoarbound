extends SceneTree

## Henry stands with his back to a wall while the view sweeps 360 degrees:
## the camera never enters the wall or his head, and fades him when it is close.
## Run: godot --headless --script tests/systems/test_tps_camera_orbit.gd

const STEP_DEG: int = 10
const FRAMES_PER_STEP: int = 20
## Wall face behind Henry, who faces -Z.
const WALL_FACE_Z: float = 0.4

var _failures: int = 0
var _frame: int = 0
var _step: int = 0
var _camera: TpsCamera
var _player: CharacterBody3D


## Stages step on physics frames, where the camera settles.
func _physics_process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_build()
		return false
	if _frame < 60 or _frame % FRAMES_PER_STEP != 0:
		return false
	if _step * STEP_DEG >= 360:
		_finish()
		return false
	_sample()
	_step += 1
	_camera.set_look(deg_to_rad(_step * STEP_DEG), -10.0)
	return false


func _build() -> void:
	_player = CharacterBody3D.new()
	var body_shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	body_shape.shape = capsule
	body_shape.position.y = 1.0
	_player.add_child(body_shape)
	root.add_child(_player)
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 3.0, 0.3)
	wall_shape.shape = box
	wall.add_child(wall_shape)
	wall.position = Vector3(0.0, 1.5, WALL_FACE_Z + 0.15)
	root.add_child(wall)
	_camera = TpsCamera.new()
	_camera.player = _player
	_camera.origin_above_feet = 0.0
	root.add_child(_camera)
	_camera.set_look(0.0, -10.0)


func _sample() -> void:
	var eye: Vector3 = _player.global_position + Vector3.UP * _camera.metrics.standing_eye
	var at: Vector3 = _camera.global_position
	var yaw: int = _step * STEP_DEG
	_check(at.z < WALL_FACE_Z, "yaw %d: camera inside or behind the wall at z=%.2f" % [yaw, at.z])
	var query := PhysicsRayQueryParameters3D.create(eye, at)
	query.exclude = [_player.get_rid()]
	var hit: Dictionary = root.get_world_3d().direct_space_state.intersect_ray(query)
	_check(hit.is_empty(), "yaw %d: the wall stands between Henry's eyes and the camera" % yaw)
	var distance: float = eye.distance_to(at)
	_check(distance >= _camera.body_fade_end,
		"yaw %d: camera collapsed to %.2f m from the eyes" % [yaw, distance])
	_check(distance >= _camera.body_fade_start or _camera.get_body_fade() > 0.0,
		"yaw %d: camera %.2f m from the eyes with Henry drawn in full" % [yaw, distance])


func _finish() -> void:
	if _failures > 0:
		push_error("tps camera orbit: %d check(s) failed" % _failures)
		quit(1)
		return
	print("tps camera orbit: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("tps camera orbit: %s" % message)
