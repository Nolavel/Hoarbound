extends SceneTree

## The direct rig with the real Henry in two tight places. A crawl space 1.4 m wide under a 1.45 m ceiling,
## crouched: walking through, a full turn in the middle, walking on. A stair ramp of 31 degrees between walls.
## The camera never stands in geometry or behind it, his eyes stay in frame, nothing jumps, and walking
## straight he is drawn in full: a camera settled at its own tight distance must not ghost him.
## Run: godot --headless --script tests/systems/test_tps_camera_direct_spaces.gd

const MAX_STEP: float = 0.2
## Most the camera may climb or drop in a frame on the ramp, metres.
const MAX_RAMP_STEP: float = 0.03

var _failures: int = 0
var _player: Player
var _camera: TpsCamera
var _walls: Node3D
var _stats: Dictionary = {}
var _last: Vector3 = Vector3.INF


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_walls = Node3D.new()
	root.add_child(_walls)
	_box(Vector3(0.0, -0.5, 0.0), Vector3(60.0, 1.0, 60.0))
	_player = (load("res://scenes/actors/player/player.tscn") as PackedScene).instantiate() as Player
	root.add_child(_player)
	_camera = (load("res://scenes/game/systems/camera/tps_camera.tscn") as PackedScene).instantiate() as TpsCamera
	_camera.player = _player
	root.add_child(_camera)
	await _crawl_space()
	await _stair_ramp()
	if _failures > 0:
		push_error("tps camera direct spaces: %d check(s) failed" % _failures)
		quit(1)
		return
	print("tps camera direct spaces: all checks passed")
	quit(0)


func _crawl_space() -> void:
	_box(Vector3(-0.85, 1.5, -3.5), Vector3(0.3, 3.0, 5.0))
	_box(Vector3(0.85, 1.5, -3.5), Vector3(0.3, 3.0, 5.0))
	_box(Vector3(0.0, 1.45 + 0.75, -3.5), Vector3(2.0, 1.5, 5.0))
	await _place(Vector3(0.0, 1.0, 1.0))
	Input.action_press(&"crouch")
	for i: int in range(40):
		await physics_frame
	Input.action_press(&"move_forward")
	_begin()
	var straight_fade: float = 0.0
	for i: int in range(900):
		await process_frame
		_sample()
		var z: float = _player.global_position.z
		if z < -2.5:
			straight_fade = maxf(straight_fade, _camera.get_body_fade())
		if z < -3.5:
			break
	Input.action_release(&"move_forward")
	_check(_player.global_position.z < -3.4, "crawl: Henry stopped at z=%.2f" % _player.global_position.z)
	_check(straight_fade < 0.05, "crawl: walking straight Henry is %.0f %% see-through" % (straight_fade * 100.0))
	var yaw: float = 0.0
	while yaw < TAU:
		yaw += deg_to_rad(1.0)
		_camera.set_look(yaw, -10.0)
		await process_frame
		_sample()
	_end("crawl", MAX_STEP)
	Input.action_release(&"crouch")
	for child: Node in _walls.get_children():
		if child.position.y > 0.0:
			child.free()


func _stair_ramp() -> void:
	var ramp := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 0.2, Vector2(3.92, 2.38).length())
	shape.shape = box
	ramp.add_child(shape)
	ramp.rotation.x = atan2(2.38, 3.92)
	ramp.position = Vector3(0.0, 1.19 - 0.1, -3.96)
	_walls.add_child(ramp)
	_box(Vector3(0.0, 1.19, -7.92), Vector3(1.4, 2.38, 4.0))
	_box(Vector3(-0.85, 2.5, -5.0), Vector3(0.3, 5.0, 10.0))
	_box(Vector3(0.85, 2.5, -5.0), Vector3(0.3, 5.0, 10.0))
	await _place(Vector3(0.0, 1.0, 1.0))
	Input.action_press(&"move_forward")
	_begin()
	var last_y: float = _camera.global_position.y
	var worst_y: float = 0.0
	for i: int in range(900):
		await process_frame
		_sample()
		worst_y = maxf(worst_y, absf(_camera.global_position.y - last_y))
		last_y = _camera.global_position.y
		if _player.global_position.z < -6.5:
			break
	Input.action_release(&"move_forward")
	_check(_player.global_position.y > 3.0, "ramp: Henry did not climb it (y=%.2f)" % _player.global_position.y)
	_check(worst_y <= MAX_RAMP_STEP, "ramp: the camera stepped %.3f m in height in one frame" % worst_y)
	_check(float(_stats["max_fade"]) < 0.05, "ramp: Henry is %.0f %% see-through on the stairs" % (float(_stats["max_fade"]) * 100.0))
	_end("ramp", MAX_STEP)


func _begin() -> void:
	_stats = {"inside": 0, "blocked": 0, "off": 0, "max_fade": 0.0, "max_step": 0.0}
	_last = Vector3.INF


func _sample() -> void:
	var space: PhysicsDirectSpaceState3D = root.get_world_3d().direct_space_state
	var at: Vector3 = _camera.global_position
	var eye: Vector3 = _camera.get_eye_position()
	var point := PhysicsPointQueryParameters3D.new()
	point.position = at
	point.exclude = [_player.get_rid()]
	_stats["inside"] += int(not space.intersect_point(point, 1).is_empty())
	var ray := PhysicsRayQueryParameters3D.create(eye, at)
	ray.exclude = [_player.get_rid()]
	_stats["blocked"] += int(not space.intersect_ray(ray).is_empty())
	_stats["off"] += int(not _camera.is_position_in_frustum(eye))
	_stats["max_fade"] = maxf(_stats["max_fade"], _camera.get_body_fade())
	var rel: Vector3 = at - _player.get_global_transform_interpolated().origin
	if _last != Vector3.INF:
		_stats["max_step"] = maxf(_stats["max_step"], rel.distance_to(_last))
	_last = rel


func _end(label: String, max_step: float) -> void:
	_check(_stats["inside"] == 0, "%s: camera inside geometry in %d frames" % [label, _stats["inside"]])
	_check(_stats["blocked"] == 0, "%s: geometry between his eyes and the camera in %d frames" % [label, _stats["blocked"]])
	_check(_stats["off"] == 0, "%s: his eyes out of the frame in %d frames" % [label, _stats["off"]])
	_check(float(_stats["max_step"]) <= max_step, "%s: the camera jumped %.2f m in a frame" % [label, _stats["max_step"]])
	print("tps camera direct spaces: %s largest step %.2f m, most faded %.2f" % [label, _stats["max_step"], _stats["max_fade"]])


func _place(at: Vector3) -> void:
	for action: StringName in [&"move_forward", &"move_backward", &"move_left", &"move_right", &"crouch"]:
		Input.action_release(action)
	_player.global_position = at
	_player.velocity = Vector3.ZERO
	_player.rotation.y = 0.0
	_player.reset_physics_interpolation()
	_camera.set_look(0.0, -10.0)
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
	_walls.add_child(body)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("tps camera direct spaces: %s" % message)
