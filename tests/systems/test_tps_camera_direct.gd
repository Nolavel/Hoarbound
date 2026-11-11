extends SceneTree

## The TPS camera's direct rig. Henry stands in a dead-end 1.3 m wide with a wall 0.4 m
## behind him while the view sweeps a full circle, resting at each step:
## - the view is exactly the look the player set: nothing turns or tilts it, at rest or pressed;
## - the camera stands behind that view, never lifted over Henry to look down on him;
## - it never enters a wall, and no wall stands between it and his eyes;
## - pressed close he turns see-through but is never hidden (no first-person view), and his eyes stay inside
##   the frame at every step (pressed 0.3 m from them, a camera at shoulder height lost his head off the top);
## - the lens widens and narrows smoothly, never in a jump;
## - a doorway never carries Henry on by itself (PassageTraversalComponent.carry_through is off).
## Run: godot --headless --path . --script res://tests/systems/test_tps_camera_direct.gd

const STEP_DEG: int = 15
const FRAMES_PER_STEP: int = 24
const WALL_FACE_Z: float = 0.4
const HALF_WIDTH: float = 0.65
const PITCH_DEG: float = -10.0
## Breathing sways the drawn pitch by up to breathing_amplitude_deg * 0.4.
const VIEW_TOLERANCE_DEG: float = 0.6
const MAX_FOV_RATE_DEG_S: float = 45.0
## Flat distance from his eyes to the camera past which they must be in frame, metres.
const ROOM_FOR_EYES: float = 0.3

var _failures: int = 0
var _frame: int = 0
var _step: int = 0
var _camera: TpsCamera
var _player: CharacterBody3D
var _last_fov: float = -1.0
var _worst_fov_rate: float = 0.0
var _closest: float = INF
var _seen_eyes: int = 0
var _most_faded: float = 0.0


func _physics_process(delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_build()
		return false
	if _last_fov >= 0.0:
		_worst_fov_rate = maxf(_worst_fov_rate, absf(_camera.fov - _last_fov) / delta)
	_last_fov = _camera.fov
	if _frame < 60 or _frame % FRAMES_PER_STEP != 0:
		return false
	if _step * STEP_DEG >= 360:
		_finish()
		return false
	_sample()
	_step += 1
	_camera.set_look(deg_to_rad(_step * STEP_DEG), PITCH_DEG)
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
	_wall(Vector3(0.0, 1.5, WALL_FACE_Z + 0.15), Vector3(6.0, 3.0, 0.3))
	_wall(Vector3(HALF_WIDTH + 0.15, 1.5, -3.0), Vector3(0.3, 3.0, 8.0))
	_wall(Vector3(-HALF_WIDTH - 0.15, 1.5, -3.0), Vector3(0.3, 3.0, 8.0))
	_camera = TpsCamera.new()
	_camera.player = _player
	_camera.origin_above_feet = 0.0
	root.add_child(_camera)
	_camera.set_look(0.0, PITCH_DEG)
	var traversal := PassageTraversalComponent.new()
	_check(not traversal.carry_through, "a doorway carries Henry on by default")
	traversal.free()


func _wall(at: Vector3, size: Vector3) -> void:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	wall.add_child(shape)
	wall.position = at
	root.add_child(wall)


func _sample() -> void:
	var yaw: int = _step * STEP_DEG
	var at: Vector3 = _camera.global_position
	var eye: Vector3 = _player.global_position + Vector3.UP * _camera.metrics.standing_eye
	## The view is the look that was set, after 24 frames of rest pressed against walls.
	var forward: Vector3 = -_camera.global_basis.z
	var drawn_yaw: float = rad_to_deg(atan2(-forward.x, -forward.z))
	var drawn_pitch: float = rad_to_deg(asin(clampf(forward.y, -1.0, 1.0)))
	_check(absf(angle_difference(deg_to_rad(drawn_yaw), deg_to_rad(float(yaw)))) < deg_to_rad(VIEW_TOLERANCE_DEG),
		"yaw %d: the view turned by itself to %.1f" % [yaw, drawn_yaw])
	_check(absf(drawn_pitch - PITCH_DEG) < VIEW_TOLERANCE_DEG, "yaw %d: the view tilted by itself to %.1f" % [yaw, drawn_pitch])
	_check(is_equal_approx(_camera.get_view_yaw(), _camera.get_yaw()), "yaw %d: an automatic offset is on the view" % yaw)
	## Behind the view, not over Henry: the boom climbs by the look's own pitch and no more.
	var rise: float = at.y - (_player.global_position.y + _camera.get_pivot_height())
	## Pressed, it may come up to his eye line (0.22 m over the shoulder joints), no higher.
	var most: float = _camera.far_distance * sin(deg_to_rad(-PITCH_DEG)) + 0.1 + (_camera.metrics.standing_eye - _camera.get_pivot_height())
	_check(rise <= most, "yaw %d: the camera rose %.2f m over the shoulder (most %.2f)" % [yaw, rise, most])
	_check(at.z < WALL_FACE_Z and absf(at.x) < HALF_WIDTH, "yaw %d: camera in a wall at (%.2f, %.2f)" % [yaw, at.x, at.z])
	var query := PhysicsRayQueryParameters3D.create(eye, at)
	query.exclude = [_player.get_rid()]
	_check(root.get_world_3d().direct_space_state.intersect_ray(query).is_empty(), "yaw %d: a wall stands between Henry's eyes and the camera" % yaw)
	_check(not _camera.is_body_hidden(), "yaw %d: Henry was hidden; it went first-person" % yaw)
	var seen: Vector3 = _camera.global_transform.affine_inverse() * eye
	var half: Vector2 = _camera.half_tangents()
	var distance: float = eye.distance_to(at)
	## With room behind his head his eyes stay in frame; with none the camera keeps out of his head instead.
	var behind: float = Vector2(at.x - eye.x, at.z - eye.z).length()
	_check(behind < ROOM_FOR_EYES or (seen.z < 0.0 and absf(seen.x) <= -seen.z * half.x and absf(seen.y) <= -seen.z * half.y),
		"yaw %d: Henry's eyes are out of the frame (%.2f, %.2f at depth %.2f)" % [yaw, seen.x, seen.y, -seen.z])
	_seen_eyes += int(behind >= ROOM_FOR_EYES)
	_check(distance >= _camera.body_fade_end - 0.005, "yaw %d: the camera stands in his head, %.2f m from his eyes" % [yaw, distance])
	_closest = minf(_closest, distance)
	_most_faded = maxf(_most_faded, _camera.get_body_fade())
	_check(distance >= _camera.direct_fade_distances.x or _camera.get_body_fade() > 0.0,
		"yaw %d: camera %.2f m from the eyes with Henry drawn in full" % [yaw, distance])


func _finish() -> void:
	_check(_worst_fov_rate <= MAX_FOV_RATE_DEG_S, "the lens jumped: %.0f deg/s" % _worst_fov_rate)
	_check(_seen_eyes > 0, "the camera never had room behind his head: the eyes-in-frame check proved nothing")
	_check(_closest < _camera.direct_fade_distances.x, "the dead end never pressed the camera (closest %.2f m): the test proves nothing" % _closest)
	print("tps camera direct: closest %.2f m, most faded %.2f, lens rate %.0f deg/s" % [_closest, _most_faded, _worst_fov_rate])
	if _failures > 0:
		push_error("tps camera direct: %d check(s) failed" % _failures)
		quit(1)
		return
	print("tps camera direct: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("tps camera direct: %s" % message)
